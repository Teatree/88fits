## The bot's goals (pass 80, lane BOT; Garry: "add a desire to explore the map and interact with totems and barrels, as
## they are an important part of the progression. Sometimes chase power-ups, sometimes chase structures"). What the bot
## knows of the map and what is worth walking to, one candidate a thing, each with a utility:
##   utility = value x taste[kind] x mood[kind] x jitter[thing] x style[kind] / (1 + distance / DIST_SCALE)
## where value says what the thing gives now (VALUES, the structures' by what they do), taste is the run's own liking for
## the kind (TASTE_LO..TASTE_HI, a roll per run from its seed), mood the same kind's roll for each MOOD_EVERY seconds of
## play (so a run goes through spells of power-ups and spells of structures), jitter a fixed roll per thing, style the
## bot's style's word on the kind (STYLE_GOALS). A thing farther than the far limit (far_limit: shorter when he is hurt
## or the last half minute cost him) is no candidate.
## What he knows: a structure, a Totem Pole or a barrel once it has been within SEE_R of him (a phone's screen round him;
## no pointer shows them), a power-up lying within POWERUP_SEE, a chest within CHEST_SEE; the arena as a grid of CELL m
## cells, a cell visited once he has been within SEE_R of its middle (explore: the unvisited cells).
## Reached only from tools and tests: nothing here names an autoload or a game class (tools compile before autoloads).
extends RefCounted

const SEE_R := 12.0
const CELL := 11.0
const POWERUP_SEE := 18.0
const CHEST_SEE := 45.0
const DIST_SCALE := 18.0
## the far limit: FAR_MIN at HP_LOW of his health or less, FAR_MAX from HP_OK up, less by DANGER_CUT x danger; a heal
## goal reaches at least HEAL_FAR
const FAR_MIN := 12.0
const FAR_MAX := 75.0
const HP_LOW := 0.35
const HP_OK := 0.8
const DANGER_CUT := 0.6
const HEAL_FAR := 35.0
const TASTE_LO := 0.6
const TASTE_HI := 1.4
const MOOD_LO := 0.7
const MOOD_HI := 1.3
const MOOD_EVERY := 120.0
const JIT_LO := 0.85
const JIT_HI := 1.15
## the sweep (the gems lying, Bot._lure's best cell worth / (distance + 2)^1.5) as a candidate: GEM_K x that worth over
## the XP the next level needs, at most GEM_CAP (gems wait on the sand; a Totem Pole near beats a pile of them)
const GEM_K := 2000.0
const GEM_CAP := 45.0
## The values (points; a card's scale): a Totem Pole's gift, a common barrel, a black one (x BARREL_RUSH_MULT with Barrel
## Rush held), a chest, the wish to explore (x the explore dial, x (0.5 + the share of the arena not seen)), the power-ups
## by effect (a heal by how hurt he is: HEAL_VALUE x (1 - health), none above HEAL_ABOVE), the structures by effect (the
## Healing Well by how hurt he is; the Uber Magnet by the XP lying on the map; the Shop only with SHOP_GOLD x the stage's
## shop price in the purse; the Stranger only while he holds STRANGER_HP of his health; the Teleport only when he is in
## trouble: under TELEPORT_HP of his health).
const V_TOTEM := 80.0
const V_BARREL := 10.0
const V_BARREL_BLACK := 28.0
const BARREL_RUSH_MULT := 1.6
const V_CHEST := 70.0
const V_EXPLORE := 30.0
const HEAL_VALUE := 90.0
const HEAL_ABOVE := 0.8
const V_POWERUP := {"vacuum": 35.0, "nuke": 25.0, "buff": 22.0, "shield": 22.0, "gold": 15.0, "pollen": 12.0, "leap": 10.0}
const V_POWERUP_OTHER := 12.0
const V_STRUCT := {"shop": 45.0, "stranger": 40.0, "buff": 28.0, "level_up": 55.0, "loot": 40.0, "dice": 20.0}
const V_STRUCT_OTHER := 15.0
const MAGNET_BASE := 15.0
const MAGNET_PER_LEVEL := 40.0
const MAGNET_MAX := 80.0
const SHOP_GOLD := 0.56
const SHOP_PRICE_BY_STAGE := [300, 500, 700]
const STRANGER_HP := 0.6
const TELEPORT_HP := 0.4
const V_TELEPORT := 60.0
## the style's word on each kind of goal (a factor on its utility; missing = 1)
const STYLE_GOALS := {
	"balanced": {},
	"damage": {"structure:war_drum": 1.5, "totem": 1.1, "explore": 0.9, "special": 1.2},
	"safety": {"structure:healing_well": 1.5, "powerup:heal": 1.5, "explore": 0.7, "barrel": 0.8, "special": 0.7},
	"greedy": {"barrel": 1.5, "chest": 1.3, "structure:loot_cache": 1.5, "gems": 1.3, "structure:uber_magnet": 1.4, "structure:shop": 0.6,
		"special": 1.3},
}
## he stands still for a structure's use within this share of its ring's radius
const STAND_FRAC := 0.55
const KINDS := ["explore", "totem", "barrel", "powerup", "structure", "chest", "gems"]
## Pass 82 (lane WATCH; Garry: "Bot should try to find the Special Enemies when they appear"), pass 90 (lane BOT; Garry:
## "I meant the Special enemy types like `Rocketeer`, `Sniper` and the `Harpooner`. The ones which spawn outside the map.
## Let's not hunt coloured fodder enemies"): a special creature type (is_special_type: its type wears the gear badge,
## EnemyDef.badge_for(), the data the game's own hit log and target priority read: today the Vulture Raider (rocketeer),
## the Saiga Sniper and the harpooner, the map's `specials` pool) is a goal of kind "special" with the option `specials`
## on; the coloured variance specials (EnemyManager.vspecial) never are. The weapons take a special first within 10 m
## (target_priority); pass 82 measured that hunting every one cost levels and falls. So he goes to find one that keeps
## off: one he has known SPECIAL_WAIT s (known: within SPECIAL_SEE m of him; the Raider sits 28 m off, the Sniper holds
## at 16 m, the harpooner keeps 12 m) that is still out of reach (past IN_REACH m or off the screen). The one he hunts
## stays known up to SPECIAL_KEEP m; once it is in reach the hunt ends (Bot.gd) and he plays on while the weapons take
## it. No hunt while a boss lives (the boss is the fight), none new under SPECIAL_HP of his health, the one under way goes
## on down to SPECIAL_HP_HELD (a gap: a health hovering at one line does not flip him between goals every half second);
## the far limit by health and danger cuts the reach as for every goal. Its value V_SPECIAL (below a chest's and a Totem
## Pole's, above the gems' cap) has no taste and no mood (always wanted), only the jitter and the style's word; the
## utility shrinks with the distance as every goal's. Bot.gd leans him into reach (HUNT_NEAR).
const SPECIAL_SEE := 30.0
const SPECIAL_KEEP := 45.0
const SPECIAL_HP := 0.5
const SPECIAL_HP_HELD := 0.4
const SPECIAL_WAIT := 5.0
## in reach: within this many metres and on the screen (= Bot.HUNT_FAR)
const IN_REACH := 9.0
const V_SPECIAL := 60.0
## Pass 85 (lane TOOLS; Garry: "Bot should also sometimes strive to pick up pick-up power-ups. Right now it feels like he
## is ignoring them"): a power-up lying is seen from PU_SEE m (a portrait screen round him; pass 80's POWERUP_SEE 18 m was
## less than the screen) and is worth what it gives now (powerup_value): a heart by how hurt he is (PU_HEAL x (1 - health)
## below PU_HEAL_ABOVE), the vacuum by the XP lying on the map (PU_VACUUM + XP lying / the next level's XP x
## PU_VACUUM_PER_LEVEL, at most PU_VACUUM_MAX), the nuke by the crowd within PU_CROWD_R m (PU_NUKE + PU_NUKE_PER a
## creature, at most PU_NUKE_MAX), a buff (rage, sprint) and the shield more while he fights (PU_BUFF / PU_SHIELD +
## PU_FIGHT x fight, fight = the crowd near / PU_FIGHT_CROWD, at most 1; the shield also by how hurt he is), the rest
## PU_OTHER. The run's taste and the spell's mood for power-ups are floored at PU_TASTE_FLOOR (a run of the lowest rolls
## still wants them; the jitter, the distance and every other goal still decide). Bot.gd commits: within PU_GRAB m of one
## he takes it whatever the crowd does.
const PU_SEE := 28.0
const PU_HEAL := 130.0
const PU_HEAL_ABOVE := 0.85
const PU_VACUUM := 30.0
const PU_VACUUM_PER_LEVEL := 70.0
const PU_VACUUM_MAX := 120.0
const PU_NUKE := 28.0
const PU_NUKE_PER := 3.0
const PU_NUKE_MAX := 90.0
const PU_BUFF := 32.0
const PU_SHIELD := 30.0
const PU_FIGHT := 30.0
const PU_FIGHT_CROWD := 8.0
const PU_CROWD_R := 8.0
const PU_GOLD := 20.0
const PU_OTHER := 15.0
const PU_TASTE_FLOOR := 0.85
const PU_GRAB := 5.0
## seconds a hunt's patience allows on top of a walk's (the lean is slower than a walk; Bot.SPECIAL_MAX_S caps the hunt)
const SPECIAL_FIGHT_S := 20.0

var seed := 1
var arena_r := 66.0
var center := Vector3.ZERO
var n := 0
## the cells: 1 visited; `inside` 1 for a cell whose middle stands inside the arena
var visited := PackedByteArray()
var inside := PackedByteArray()
var cells_inside := 0
var cells_seen := 0
## instance id -> true for every structure seen; 1 for every barrel seen
var seen_struct: Dictionary = {}
var seen_barrel := PackedByteArray()
## a thing's key -> the play second it may be a goal again (given up on)
var resting: Dictionary = {}
## pass 82: a special's key -> the play second he first knew it
var special_seen: Dictionary = {}
var taste: Dictionary = {}


func _init(p_seed: int = 1) -> void:
	seed = p_seed
	for k in KINDS:
		taste[k] = TASTE_LO + (TASTE_HI - TASTE_LO) * roll01(hash([seed, "taste", k]))


## A fixed roll in [0, 1) from a hash.
static func roll01(h: int) -> float:
	return float(absi(h) % 100000) / 100000.0


## The arena's grid (a square of CELL m cells round the flats' middle, those inside the arena counted).
func setup_map(map) -> void:
	if map != null:
		if map.get("arena_radius") != null:
			arena_r = float(map.arena_radius)
		if map.get("flats_center") != null:
			center = map.flats_center
	n = int(ceil(arena_r * 2.0 / CELL))
	visited.resize(n * n)
	visited.fill(0)
	inside.resize(n * n)
	cells_inside = 0
	for i in range(n * n):
		var c := cell_mid(i)
		var ok := Vector2(c.x - center.x, c.z - center.z).length() < arena_r - 3.0
		inside[i] = 1 if ok else 0
		if ok:
			cells_inside += 1


func cell_mid(i: int) -> Vector3:
	var cx := i % maxi(n, 1)
	var cz := i / maxi(n, 1)
	return Vector3(center.x - arena_r + (float(cx) + 0.5) * CELL, 0.0, center.z - arena_r + (float(cz) + 0.5) * CELL)


func cell_of(p: Vector3) -> int:
	var cx := floori((p.x - center.x + arena_r) / CELL)
	var cz := floori((p.z - center.z + arena_r) / CELL)
	if cx < 0 or cz < 0 or cx >= n or cz >= n:
		return -1
	return cz * n + cx


## The share of the arena's cells seen.
func seen_share() -> float:
	return float(cells_seen) / float(maxi(cells_inside, 1))


## What he sees from `me`: the cells, the structures and the barrels within SEE_R.
func observe(game: Node, me: Vector3) -> void:
	if n <= 0:
		setup_map(game.map)
	var r := int(ceil(SEE_R / CELL)) + 1
	var c0 := cell_of(me)
	if c0 >= 0:
		var cx0 := c0 % n
		var cz0 := c0 / n
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var cx := cx0 + dx
				var cz := cz0 + dz
				if cx < 0 or cz < 0 or cx >= n or cz >= n:
					continue
				var i := cz * n + cx
				if visited[i] == 1:
					continue
				var m := cell_mid(i)
				if Vector2(m.x - me.x, m.z - me.z).length() <= SEE_R:
					visited[i] = 1
					if inside[i] == 1:
						cells_seen += 1
	var sm = game.get("structures")
	if sm != null:
		for s in sm.items:
			if not is_instance_valid(s):
				continue
			var at: Vector3 = (s as Node3D).global_position
			if Vector2(at.x - me.x, at.z - me.z).length() <= SEE_R:
				seen_struct[s.get_instance_id()] = true
	var bf = game.get("barrels")
	if bf != null:
		var pos: PackedVector3Array = bf.pos
		if seen_barrel.size() != pos.size():
			seen_barrel.resize(pos.size())
			seen_barrel.fill(0)
		for i in range(pos.size()):
			if seen_barrel[i] == 0 and Vector2(pos[i].x - me.x, pos[i].z - me.z).length() <= SEE_R:
				seen_barrel[i] = 1


## How far a goal may lie now: FAR_MIN when he is at HP_LOW or less, FAR_MAX from HP_OK, cut by danger.
static func far_limit(hp_frac: float, danger: float) -> float:
	var ok := clampf((hp_frac - HP_LOW) / (HP_OK - HP_LOW), 0.0, 1.0) * (1.0 - DANGER_CUT * clampf(danger, 0.0, 1.0))
	return lerpf(FAR_MIN, FAR_MAX, ok)


func mood(kind: String, t: float) -> float:
	return MOOD_LO + (MOOD_HI - MOOD_LO) * roll01(hash([seed, "mood", kind, int(t / MOOD_EVERY)]))


func jitter(key: String) -> float:
	return JIT_LO + (JIT_HI - JIT_LO) * roll01(hash([seed, "jit", key]))


static func style_mult(style: String, kind: String, sub: String) -> float:
	var t: Dictionary = STYLE_GOALS.get(style, {})
	return float(t.get(sub, t.get(kind, 1.0)))


## `d` with `extra`'s keys laid over (a candidate's handles: ref (an instance id), index (a barrel), cell, stand (the
## radius he stands still inside), interact (seconds), sid (a structure's id)).
static func _with(d: Dictionary, extra: Dictionary) -> Dictionary:
	for k in extra:
		d[k] = extra[k]
	return d


## A candidate: {kind, what (the intent), key, at, value, u, why, d} (+ its handles, _with). `c` is the planner's view: me, t,
## hp_frac, danger, style, opts, boss (Vector3.INF none), leash (bool).
func _cand(c: Dictionary, kind: String, what: String, key: String, at: Vector3, value: float, why: String, sub: String = "") -> Dictionary:
	var me: Vector3 = c["me"]
	var d := Vector2(at.x - me.x, at.z - me.z).length()
	var tm := float(taste.get(kind, 1.0)) * mood(kind, float(c["t"]))
	# pass 85: a run's taste for power-ups never falls under PU_TASTE_FLOOR
	if kind == "powerup":
		tm = maxf(tm, PU_TASTE_FLOOR)
	var u := value * tm * jitter(key) \
		* style_mult(str(c["style"]), kind, sub if sub != "" else kind) / (1.0 + d / DIST_SCALE)
	return {"kind": kind, "what": what, "key": key, "at": at, "value": value, "u": u, "why": why, "d": d}


## Every candidate now (see the file's head), best first. `game` the Game node; `run` the Run autoload; `c` as _cand.
func candidates(game: Node, run, c: Dictionary) -> Array:
	var out: Array = []
	var me: Vector3 = c["me"]
	var t := float(c["t"])
	var hp := float(c["hp_frac"])
	var danger := float(c["danger"])
	var o: Dictionary = c["opts"]
	var far := far_limit(hp, danger)
	var boss: Vector3 = c["boss"]
	var leash := bool(c["leash"])
	var reach := func(at: Vector3, lim: float) -> bool:
		if Vector2(at.x - me.x, at.z - me.z).length() > lim:
			return false
		return not leash or boss == Vector3.INF or Vector2(at.x - boss.x, at.z - boss.z).length() <= 10.0
	# structures and Totem Poles seen, not used, standing (not floating down or flying off)
	var sm = game.get("structures")
	if sm != null and (bool(o["totems"]) or bool(o["structures"])):
		for s in sm.items:
			if not is_instance_valid(s) or bool(s.used) or bool(s.get("arriving")) or bool(s.get("leaving")) or s.def == null:
				continue
			if not seen_struct.has(s.get_instance_id()):
				continue
			var key := "st:%d" % s.get_instance_id()
			if float(resting.get(key, -1.0)) > t:
				continue
			var at: Vector3 = (s as Node3D).global_position
			var eff := str(s.def.effect_kind)
			var sid := str(s.def.id)
			var nm := str(s.def.display_name)
			if eff == "totem":
				if bool(o["totems"]) and reach.call(at, far):
					out.append(_with(_cand(c, "totem", "totem", key, at, V_TOTEM, "a Totem Pole's gift"), {"ref": s.get_instance_id(),
						"stand": float(s.def.radius) * STAND_FRAC, "interact": float(s.def.interact_time), "sid": sid}))
				continue
			if not bool(o["structures"]):
				continue
			var v := 0.0
			var why := ""
			var lim := far
			match eff:
				"heal":
					if hp < HEAL_ABOVE:
						v = HEAL_VALUE * (1.0 - hp)
						lim = maxf(far, HEAL_FAR)
						why = "hurt (%d%% HP): the %s" % [roundi(hp * 100.0), nm]
				"vacuum_all":
					var lying := float(c.get("xp_lying", 0.0))
					var need := maxf(float(c.get("xp_need", 1.0)), 1.0)
					v = minf(MAGNET_BASE + lying / need * MAGNET_PER_LEVEL, MAGNET_MAX)
					why = "%d XP lying: the %s" % [roundi(lying), nm]
				"shop":
					var stage := clampi(int(run.stage), 0, SHOP_PRICE_BY_STAGE.size() - 1)
					if bool(o["shop"]) and int(run.run_gold) >= int(SHOP_PRICE_BY_STAGE[stage] * SHOP_GOLD):
						v = float(V_STRUCT["shop"])
						why = "%d gold to spend: the %s" % [int(run.run_gold), nm]
				"stranger":
					if bool(o["stranger"]) and hp >= STRANGER_HP:
						v = float(V_STRUCT["stranger"])
						why = "healthy enough (%d%% HP) to deal with the Stranger" % roundi(hp * 100.0)
				"teleport":
					if hp < TELEPORT_HP and danger > 0.3:
						v = V_TELEPORT
						why = "in trouble: the %s" % nm
				"bank":
					v = 0.0
				_:
					v = float(V_STRUCT.get(eff, V_STRUCT_OTHER))
					why = "the %s" % nm
			if v > 0.0 and reach.call(at, lim):
				out.append(_with(_cand(c, "structure", "structure:" + sid, key, at, v, why, "structure:" + sid), {"ref": s.get_instance_id(),
					"stand": float(s.def.radius) * STAND_FRAC, "interact": float(s.def.interact_time), "sid": sid, "name": nm}))
	# barrels seen
	var bf = game.get("barrels")
	if bf != null and bool(o["barrels"]):
		var rush := float(run.player_sheet.get_stat("barrel_speed", 0.0)) > 0.0
		var pos: PackedVector3Array = bf.pos
		for i in range(mini(pos.size(), seen_barrel.size())):
			if bf.alive[i] == 0 or seen_barrel[i] == 0:
				continue
			var key := "barrel:%d" % i
			if float(resting.get(key, -1.0)) > t or not reach.call(pos[i], far):
				continue
			# pass 116 (lane MAP): the coins barrel (1) and the power-up barrel (2) are the good ones
			var black: bool = bf.light[i] >= 1
			var v := (V_BARREL_BLACK if black else V_BARREL) * (BARREL_RUSH_MULT if rush else 1.0)
			out.append(_with(_cand(c, "barrel", "barrel", key, pos[i], v, ("a black barrel" if black else "a barrel") + (" (Barrel Rush)" if rush else "")),
				{"index": i}))
	# power-ups lying in sight
	var pk = game.pickups
	if pk != null and bool(o["powerups"]):
		for sp in pk.specials:
			if not is_instance_valid(sp) or bool(sp.taken) or sp.def == null:
				continue
			var at: Vector3 = (sp as Node3D).global_position
			var key := "pu:%d" % sp.get_instance_id()
			if float(resting.get(key, -1.0)) > t:
				continue
			var eff := str(sp.def.effect_kind)
			# pass 85: worth what it gives now (powerup_value), seen from PU_SEE m (a heart from there whatever the far limit)
			var v := powerup_value(eff, c)
			var lim := PU_SEE if eff == "heal" else minf(far, PU_SEE)
			var d := Vector2(at.x - me.x, at.z - me.z).length()
			# it must still lie there when he arrives (Powerup.life)
			if sp.get("life") != null and float(sp.life) < d / 3.6 + 1.0:
				continue
			if v > 0.0 and reach.call(at, lim):
				var pname := str(sp.def.display_name)
				out.append(_with(_cand(c, "powerup", "powerup", key, at, v, "a %s lying %d m off%s" % [pname, roundi(d), powerup_why(eff, c)], "powerup:" + eff),
					{"ref": sp.get_instance_id(), "name": pname}))
	# chests in sight
	if pk != null:
		for ch in pk.chests:
			if not is_instance_valid(ch) or bool(ch.opened) or bool(ch.boss):
				continue
			var at: Vector3 = (ch as Node3D).global_position
			var key := "chest:%d" % ch.get_instance_id()
			if float(resting.get(key, -1.0)) > t or not reach.call(at, minf(maxf(far, 20.0), CHEST_SEE)):
				continue
			out.append(_with(_cand(c, "chest", "chest", key, at, V_CHEST, "a chest %d m off" % roundi(Vector2(at.x - me.x, at.z - me.z).length())),
				{"ref": ch.get_instance_id()}))
	# explore: the unvisited cell worth the most
	var ex := float(o["explore"])
	if ex > 0.0 and n > 0 and not (leash and boss != Vector3.INF):
		var best := {}
		var v := V_EXPLORE * ex * (0.5 + (1.0 - seen_share()))
		for i in range(n * n):
			if inside[i] == 0 or visited[i] == 1:
				continue
			var key := "cell:%d" % i
			if float(resting.get(key, -1.0)) > t:
				continue
			var m := cell_mid(i)
			if not reach.call(m, far):
				continue
			var cd := _with(_cand(c, "explore", "explore", key, m, v, "to see the map (%d%% seen)" % roundi(seen_share() * 100.0)), {"cell": i})
			if best.is_empty() or float(cd["u"]) > float(best["u"]):
				best = cd
		if not best.is_empty():
			out.append(best)
	# the gems (the sweep)
	var ls := float(c.get("lure_s", 0.0))
	if ls > 0.0 and c.get("lure_at", Vector3.INF) != Vector3.INF:
		var lat: Vector3 = c["lure_at"]
		var gv := minf(GEM_K * ls / maxf(float(c.get("xp_need", 1.0)), 1.0), GEM_CAP)
		var g := {"kind": "gems", "what": "sweep", "key": "gems", "at": lat, "value": gv, "d": Vector2(lat.x - me.x, lat.z - me.z).length(),
			"why": "the gems lying %d m off" % roundi(Vector2(lat.x - me.x, lat.z - me.z).length())}
		g["u"] = gv * float(taste.get("gems", 1.0)) * style_mult(str(c["style"]), "gems", "gems")
		out.append(g)
	# pass 82: the specials he knows of (special_candidates)
	if bool(o.get("specials", false)):
		out.append_array(special_candidates(game, c, far))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["u"]) > float(b["u"]))
	return out


## The special creature types alive that he knows of and that keep off (see SPECIAL_WAIT above; SPECIAL_KEEP and in
## reach too for the one held: `c.held_key`), each a candidate of kind "special" ({..., index, serial, sid (its creature
## id), name, fight (SPECIAL_FIGHT_S)}); none while a boss lives, none new under SPECIAL_HP of his health (the one held:
## SPECIAL_HP_HELD), none past the far limit `far`. Pass 90: only the special creature types (is_special_type), never a
## coloured variance special.
func special_candidates(game: Node, c: Dictionary, far: float) -> Array:
	var out: Array = []
	var em = game.get("enemies")
	var hp := float(c["hp_frac"])
	if em == null or hp < SPECIAL_HP_HELD or c["boss"] != Vector3.INF:
		return out
	var me: Vector3 = c["me"]
	var t := float(c["t"])
	var held := str(c.get("held_key", ""))
	var dying := int(em.STATE_DYING)
	var os = em.get("onscreen")
	for i in range(int(em.MAX)):
		if em.alive[i] != 1 or int(em.state[i]) == dying or not is_special_type(em, i):
			continue
		var key := special_key(i, int(em.serial[i]))
		if float(resting.get(key, -1.0)) > t or (hp < SPECIAL_HP and key != held):
			continue
		var at: Vector3 = em.pos[i]
		var d := Vector2(at.x - me.x, at.z - me.z).length()
		if d > minf(far, SPECIAL_KEEP if key == held else SPECIAL_SEE):
			continue
		# known since when; one in reach (or not known long enough) is the weapons', unless he hunts it already
		if not special_seen.has(key):
			special_seen[key] = t
		var on: bool = not (os is PackedByteArray) or i >= (os as PackedByteArray).size() or (os as PackedByteArray)[i] == 1
		if key != held and (t - float(special_seen[key]) < SPECIAL_WAIT or (d <= IN_REACH and on)):
			continue
		var def = em.types[em.type_idx[i]]["def"]
		var nm := str(def.display_name)
		var u := V_SPECIAL * jitter(key) * style_mult(str(c["style"]), "special", "special") / (1.0 + d / DIST_SCALE)
		out.append({"kind": "special", "what": "special", "key": key, "at": at, "value": V_SPECIAL, "u": u, "d": d,
			"why": "a special: %s, out of reach %d s" % [nm, roundi(t - float(special_seen[key]))], "index": i, "serial": int(em.serial[i]), "sid": str(def.id), "name": nm,
			"fight": SPECIAL_FIGHT_S})
	return out


## Pass 90: whether creature `i` of the crowd `em` is of a special creature type: its type wears the gear badge (the type
## entry's "badge", EnemyDef.badge_for(); a type entry without one asks its def). A coloured variance special of a plain
## creature is not (vspecial is never read here).
static func is_special_type(em, i: int) -> bool:
	if em == null:
		return false
	var types = em.get("types")
	var tix = em.get("type_idx")
	if not (types is Array) or not (tix is PackedInt32Array) or i < 0 or i >= (tix as PackedInt32Array).size():
		return false
	var ti := int(tix[i])
	if ti < 0 or ti >= (types as Array).size() or not (types[ti] is Dictionary):
		return false
	var te: Dictionary = types[ti]
	if te.has("badge"):
		return str(te["badge"]) == "gear"
	var def = te.get("def")
	return def != null and def.has_method("badge_for") and str(def.badge_for()) == "gear"


## A special's key: its slot and its serial (a slot is used again by the next creature).
static func special_key(i: int, serial: int) -> String:
	return "sp:%d:%d" % [i, serial]


## Pass 85: what a power-up of effect `eff` is worth now (see PU_* above); `c` the planner's view (hp_frac, crowd: the
## creatures within PU_CROWD_R m, xp_lying, xp_need). 0 = no goal (a heart while he is well).
static func powerup_value(eff: String, c: Dictionary) -> float:
	var hp := float(c.get("hp_frac", 1.0))
	var crowd := float(c.get("crowd", 0.0))
	var fight := clampf(crowd / PU_FIGHT_CROWD, 0.0, 1.0)
	match eff:
		"heal":
			return PU_HEAL * (1.0 - hp) if hp < PU_HEAL_ABOVE else 0.0
		"vacuum", "magnet":
			# (pass 95, lane WORLD: the Magnet power-up is a timed wide pull, priced like the vacuum by the XP lying)
			var need := maxf(float(c.get("xp_need", 1.0)), 1.0)
			return minf(PU_VACUUM + float(c.get("xp_lying", 0.0)) / need * PU_VACUUM_PER_LEVEL, PU_VACUUM_MAX)
		"nuke":
			return minf(PU_NUKE + PU_NUKE_PER * crowd, PU_NUKE_MAX)
		"buff":
			return PU_BUFF + PU_FIGHT * fight
		"shield":
			return PU_SHIELD + PU_FIGHT * maxf(fight, 1.0 - hp)
		"gold":
			return PU_GOLD
	return PU_OTHER


## Pass 85: why a power-up is worth it now, for the goal's reason (", hurt (40% HP)", ", 12 creatures close", ...).
static func powerup_why(eff: String, c: Dictionary) -> String:
	var crowd := int(c.get("crowd", 0))
	match eff:
		"heal":
			return ", hurt (%d%% HP)" % roundi(float(c.get("hp_frac", 1.0)) * 100.0)
		"vacuum", "magnet":
			return ", %d XP lying" % roundi(float(c.get("xp_lying", 0.0)))
		"nuke", "buff", "shield":
			if crowd > 0:
				return ", %d creature%s close" % [crowd, "" if crowd == 1 else "s"]
	return ""

## A made-up run for the Results screen's captures, its touch audit and its tests (pass 72): the Drifter's 10:00
## extraction on stage 2 told as a RunTimeline (11:30 of play: the King's fight held the stage clock), with a purse that
## climbs, an Elite's and a boss's purse, a shop's spend, waves of kills with a lull in the boss fight and a horde after
## it, specials, two Elites, the King, the stages, and seven damage sources joining one after another. `died` adds two
## falls (one he got up from: the revive's blast joins) and ends the run on the second. Loaded at run time (tools compile
## before the autoloads exist): fill(run, save, quest_tracker).
extends RefCounted

const PLAY := 690.0
const START := "revolver"
## [id, damage, owned at (s, -1: never owned), first hit at (s)]
const SOURCES := [
	["revolver", 4210.0, 0.0, 1.0],
	["boomstick", 6540.0, 38.0, 40.0],
	["burn", 160.0, -1.0, 150.0],
	["molotov", 1690.0, 148.0, 150.0],
	["big_mouth", 3410.0, 262.0, 263.0],
	["supply_drop", 260.0, 355.0, 380.0],
	["blast", 420.0, -1.0, 420.0],
	["turret_buddy", 2560.0, 520.0, 522.0],
]


static func fill(run: Node, save: Node, qt, died: bool = false) -> void:
	var tl: RunTimeline = RunTimeline.new()
	tl.attached = true
	tl.t = PLAY
	tl.start_weapon = START
	var rng := RandomNumberGenerator.new()
	rng.seed = 72
	var purse := 0.0
	var dmg := 0.0
	var dmg_total := 0.0
	for s in SOURCES:
		dmg_total += float(s[1])
	if died:
		dmg_total += 900.0
	var kills_total := 0
	for sec in int(PLAY):
		var tt := float(sec)
		# kills a second: a slow start, waves every 40 s, the King's fight a lull (430-470), a horde after it
		var base := lerpf(0.4, 3.6, tt / PLAY) * (0.65 + 0.35 * sin(tt / 40.0 * TAU))
		if tt > 430.0 and tt < 470.0:
			base *= 0.25
		if tt > 480.0 and tt < 520.0:
			base *= 2.2
		var k := int(floor(base + rng.randf()))
		tl.kills.append(maxi(k, 0))
		kills_total += maxi(k, 0)
		# the purse: coins with the kills, an Elite's purse at 215 and 645, the King's at 470, a shop at 300
		purse += float(k) * 0.9 + (450.0 if sec == 215 else 0.0) + (1300.0 if sec == 470 else 0.0) + (750.0 if sec == 645 else 0.0)
		if sec == 300:
			purse -= 180.0
		if died and sec == 600:
			purse -= 100.0
		tl.purse.append(int(purse))
		dmg += dmg_total / PLAY * (0.4 + 1.2 * tt / PLAY)
		tl.damage.append(dmg)
	for sec in [62, 95, 121, 170, 188, 240, 251, 290, 333, 351, 372, 401, 455, 498, 502, 507, 533, 560, 588, 610, 633, 670]:
		tl.markers.append([float(sec), RunTimeline.KIND_SPECIAL])
	tl.markers.append([215.0, RunTimeline.KIND_ELITE])
	tl.markers.append([645.0, RunTimeline.KIND_ELITE])
	tl.markers.append([470.0, RunTimeline.KIND_BOSS])
	if died:
		tl.markers.append([600.0, RunTimeline.KIND_DOWN])
		tl.markers.append([PLAY - 0.5, RunTimeline.KIND_DOWN])
	tl.markers.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	tl.stages.append([480.0, 1])
	var table := {}
	for s in SOURCES:
		var e := {"owned": float(s[2]), "hit": float(s[3]), "curve": PackedFloat32Array()}
		tl.sources[str(s[0])] = e
		table[str(s[0])] = float(s[1])
	if died:
		tl.sources["revive"] = {"owned": -1.0, "hit": 601.0, "curve": PackedFloat32Array()}
		table["revive"] = 900.0
	# the counted unlocks as the run began: kills (all time), skeletons, chests
	tl.quests_before = {"unlock_adrenaline": 120, "unlock_ironwood": 120, "unlock_tumbleweed": 40, "unlock_rocket_pod": 1}
	run.set("timeline", tl)
	run.set("character", run.get_node("/root/Registry").character("drifter"))
	run.set("extracted", not died)
	run.set("died", died)
	run.set("elapsed", 600.0 if not died else PLAY - 90.0)
	run.set("stage", 1)
	run.set("level", 47)
	run.set("kills", kills_total)
	run.set("chests_opened", 3)
	run.set("evolutions", 0)
	run.set("run_gold", int(purse))
	run.set("damage_by_weapon", table)
	run.set("last_result", {"gold_before": 104711, "banked": int(purse), "lost": 0, "strongbox": 0, "prev_best": {"time": 480.0}})
	# the save as the run left it: the totals the unlocks count, the Turret Buddy's quest done in this run
	var totals: Dictionary = save.get("data")["totals"]
	totals["kills"] = 380
	totals["chests"] = 2
	if not (totals.get("kills_of_enemy") is Dictionary):
		totals["kills_of_enemy"] = {}
	totals["kills_of_enemy"]["skeleton"] = 112
	save.call("mark_quest", "unlock_turret_buddy")
	save.call("mark_hint", "results")
	qt.just_completed = ["unlock_turret_buddy"]

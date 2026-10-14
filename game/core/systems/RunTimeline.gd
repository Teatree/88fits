## The run's story for the Results screen (pass 72, Garry: the coins "follow the sequence of how Player had collected
## their gold in the game at the pace that they did", a kills chart with the deaths, bosses, Elites and specials marked,
## the damage sources "added at the sequence that they were acquired"). Kept on Run (`Run.timeline`, a new one at every
## Run.start); Game attaches it to the run's signals (`attach`) and ticks its clock with unpaused play only (`tick`, as
## the run recorder's play_t), so a boss fight, whose stage clock stands still, keeps its seconds. It holds:
## - the purse at the end of every second (gold in and out, so it ends at what the run banks: Game.bank_run_end),
## - the kills in every second, and a marker with its moment for each boss, Elite and special kill and each time the hero
##   went down (KIND_*), and the moments the stages began,
## - all the damage dealt by the end of every second (the Results' Damage counter), and for every damage id (what
##   Run.add_damage was handed): the moment it was first owned (a weapon, an evolution, a passive, a perk or a mutation:
##   the build's scan on Run.build_changed), the moment it first hit (fire, poison, the revive's blast, a power-up), and
##   its damage every SRC_STEP seconds,
## - the starting weapon (the first weapon owned), and every counted quest's progress as the run began (the Results'
##   unlock bars fill from it).
## Cost: one int add a kill or a coin, one pass over the damage table a second, one over the build when it changes.
class_name RunTimeline
extends RefCounted

const KIND_PLAIN := 0
const KIND_SPECIAL := 1
const KIND_ELITE := 2
const KIND_BOSS := 3
## The hero went down (a grave on the Results' chart).
const KIND_DOWN := 4
## The marker kinds' names (the Results' badges: art/ui/badges/<name>.png).
const KIND_NAMES := ["", "gear", "crown", "skull", "grave"]
## Seconds between two samples of a source's damage.
const SRC_STEP := 5.0

## Seconds of unpaused play since the run began.
var t := 0.0
## The purse at the end of second k (index k), the kills in second k, all damage dealt by the end of second k.
var purse := PackedInt32Array()
var kills := PackedInt32Array()
var damage := PackedFloat32Array()
## [t, kind] for every boss, Elite and special kill and every down, in the order they came.
var markers: Array = []
## [t, stage index] for every stage that began after the first.
var stages: Array = []
## Damage id -> {"owned": t or -1, "hit": t or -1, "curve": PackedFloat32Array (its damage by k x SRC_STEP)}.
var sources: Dictionary = {}
var start_weapon := ""
## Quest id -> its progress (QuestTracker.progress().x) as the run began, for the counted quests not done yet.
var quests_before: Dictionary = {}
var attached := false
var _purse_now := 0
var _src_acc := 0.0
var _em: WeakRef = null


## Joins the run's game: the creature deaths (their kind read off the crowd as they fall), the hero's downs, the stages,
## the purse and the build. Called once by Game._ready for a real run (never in the arena).
func attach(game: Node) -> void:
	attached = true
	var em = game.get("enemies")
	if em != null and em is Object and em.has_signal("creature_dying"):
		_em = weakref(em)
		em.connect("creature_dying", _on_dying)
	var pl = game.get("player")
	if pl != null and pl is Object and pl.has_signal("died"):
		pl.connect("died", down)
	var dir = game.get("director")
	if dir != null and dir is Object and dir.has_signal("stage_started"):
		dir.connect("stage_started", _on_stage)
	var run := _run()
	if run:
		run.connect("gold_changed", _on_gold)
		run.connect("build_changed", scan_build)
		_purse_now = int(run.get("run_gold"))
	quests_before = quest_progress()
	scan_build()


## One frame of unpaused play: the clock, and a sample at every whole second (and every SRC_STEP for the sources).
func tick(delta: float) -> void:
	if not attached:
		return
	t += delta
	while purse.size() < int(t):
		sample()
	_src_acc += delta
	if _src_acc >= SRC_STEP:
		_src_acc -= SRC_STEP
		sample_sources()


## The second that just ended: the purse, the damage so far, and the first hit of any new damage id.
func sample() -> void:
	purse.append(_purse_now)
	var total := 0.0
	var run := _run()
	var table: Dictionary = run.get("damage_by_weapon") if run else {}
	for id in table:
		total += float(table[id])
		var e: Dictionary = _source(str(id))
		if float(e["hit"]) < 0.0:
			e["hit"] = float(purse.size() - 1)
	damage.append(total)
	if kills.size() < purse.size():
		kills.resize(purse.size())


## Every source's damage so far, one more point on each curve.
func sample_sources() -> void:
	var run := _run()
	var table: Dictionary = run.get("damage_by_weapon") if run else {}
	var k := int(round(t / SRC_STEP))
	for id in table:
		var e: Dictionary = _source(str(id))
		var c: PackedFloat32Array = e["curve"]
		while c.size() < k - 1:
			c.append(0.0 if c.is_empty() else c[c.size() - 1])
		c.append(float(table[id]))
		e["curve"] = c


## A kill of `kind` now.
func kill(kind: int) -> void:
	var s := int(t)
	if kills.size() <= s:
		kills.resize(s + 1)
	kills[s] += 1
	if kind != KIND_PLAIN:
		markers.append([t, kind])


## The hero went down now (every fall: the one he got up from and the last).
func down() -> void:
	markers.append([t, KIND_DOWN])


## What a falling creature was (EnemyManager.creature_dying): a boss, an Elite (the archetype or one wearing an elite
## modifier), a special (a variance special: the dark, big one; or a creature with the gear badge: the rocketeer, the
## harpooner), else plain. A training dummy is nothing (-1).
static func kind_of(em: Object, i: int) -> int:
	var ti: int = em.get("type_idx")[i]
	var types: Array = em.get("types")
	if ti < 0 or ti >= types.size():
		return KIND_PLAIN
	var def: EnemyDef = types[ti]["def"]
	var dummies: PackedByteArray = em.get("_t_dummy")
	if ti < dummies.size() and dummies[ti] != 0:
		return -1
	if i == int(em.get("boss_index")) or def.archetype == "boss":
		return KIND_BOSS
	if em.get("elite_idx")[i] >= 0 or def.archetype == "elite":
		return KIND_ELITE
	if em.get("vspecial")[i] == 1 or def.badge_for() == "gear":
		return KIND_SPECIAL
	return KIND_PLAIN


func _on_dying(i: int, _weapon_id: String) -> void:
	var em: Object = _em.get_ref() if _em else null
	if em == null:
		kill(KIND_PLAIN)
		return
	var k := kind_of(em, i)
	if k >= 0:
		kill(k)


func _on_gold(run_gold: int) -> void:
	_purse_now = run_gold


func _on_stage(s: int) -> void:
	if s > 0:
		stages.append([t, s])


## Everything the hero holds now that was not held before is owned from now (the starting weapon at 0).
func scan_build() -> void:
	var run := _run()
	if run == null:
		return
	for w in run.get("weapons"):
		var id: String = (w as WeaponInstance).def.id
		if start_weapon == "":
			start_weapon = id
		own(id)
	for id in (run.get("passives") as Dictionary).keys():
		own(str(id))
	for id in run.get("perks"):
		own(str(id))
	var muts: Dictionary = run.get("mutations")
	for fam in muts:
		for m in muts[fam]:
			own(str(m))


## `id` owned from now, unless it was owned before.
func own(id: String) -> void:
	var e := _source(id)
	if float(e["owned"]) < 0.0:
		e["owned"] = t


## When a damage id joined the run: when it was first owned, else when it first hit; INF for one never seen.
func joined(id: String) -> float:
	if not sources.has(id):
		return INF
	var e: Dictionary = sources[id]
	if float(e["owned"]) >= 0.0:
		return float(e["owned"])
	if float(e["hit"]) >= 0.0:
		return float(e["hit"])
	return INF


func _source(id: String) -> Dictionary:
	if not sources.has(id):
		sources[id] = {"owned": -1.0, "hit": -1.0, "curve": PackedFloat32Array()}
	return sources[id]


func _run() -> Node:
	return _autoload("Run")


## An autoload looked up at run time (the record is made before a tool's autoloads exist).
static func _autoload(name: String) -> Node:
	var ml := Engine.get_main_loop() as SceneTree
	return ml.root.get_node_or_null(name) if ml and ml.root else null


# ---------------------------------------------------------------- reading it back (the Results screen)

## The run's length on this clock (at least a second).
func length() -> float:
	return maxf(t, 1.0)


## Whether anything was recorded (a tool or a test that fills Run by hand has an empty story).
func is_empty() -> bool:
	return purse.is_empty() and kills.is_empty() and markers.is_empty()


## A curve's value at `frac` (0..1) of the run: `samples[k]` is the value at second k + 1, 0 at the start, `final` at
## the end (the last part second runs from the last sample to `final`); linear between.
func value_at(samples, final: float, frac: float) -> float:
	var f := clampf(frac, 0.0, 1.0)
	var n: int = samples.size()
	if n == 0:
		return final * f
	if f >= 1.0:
		return final
	var at := f * length()
	# inside second k: from its start's value (the sample before it, 0 at the start) to its end's (the last part second
	# ends on `final`)
	var k := int(floor(at))
	var a: float = 0.0 if k == 0 else float(samples[mini(k - 1, n - 1)])
	var b: float = final if k >= n else float(samples[k])
	var t1: float = minf(float(k + 1), length())
	return lerpf(a, b, clampf((at - float(k)) / maxf(t1 - float(k), 0.001), 0.0, 1.0))


## Kills at the end of each second, summed.
func kills_so_far() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var sum := 0.0
	for k in kills:
		sum += float(k)
		out.append(sum)
	return out


## A damage id's damage so far `at` seconds into the run (pass 74: the Results' source rows grow with the chart's line):
## its SRC_STEP samples (sample k is its damage at (k + 1) x SRC_STEP), linear between them, 0 at the start and `final`
## (what the run counted for it) at the end, so it only grows; -1 when the record has no sample of it (a tool's run, or
## a source that first hit in the last few seconds).
func source_damage_at(id: String, at: float, final: float) -> float:
	if not sources.has(id):
		return -1.0
	var c: PackedFloat32Array = (sources[id] as Dictionary).get("curve", PackedFloat32Array())
	var n := c.size()
	if n == 0:
		return -1.0
	if at <= 0.0:
		return 0.0
	if at >= length():
		return final
	var k := int(floor(at / SRC_STEP))
	if k < n:
		var y0: float = 0.0 if k == 0 else float(c[k - 1])
		return minf(lerpf(y0, float(c[k]), (at - float(k) * SRC_STEP) / SRC_STEP), final)
	# past the last sample: from it to the end
	var x0 := float(n) * SRC_STEP
	return lerpf(minf(float(c[n - 1]), final), final, clampf((at - x0) / maxf(length() - x0, 0.001), 0.0, 1.0))


## The kills in `n` equal slices of the run (the chart's bars), as a count per slice.
func kill_slices(n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(n, 1))
	var span := length() / float(out.size())
	for s in kills.size():
		var idx := mini(int(floor((float(s) + 0.5) / span)), out.size() - 1)
		out[idx] += float(kills[s])
	return out


## The quests counted across runs that are not done yet, with their progress now: {id: progress.x}.
static func quest_progress() -> Dictionary:
	var out := {}
	var reg := _autoload("Registry")
	var save := _autoload("Save")
	if reg == null or save == null:
		return out
	for q: QuestDef in (reg.get("quests") as Dictionary).values():
		if save.call("quest_done", q.id) or not reg.call("quest_visible", q):
			continue
		var p := QuestTracker.progress(q)
		if p.y > 0:
			out[q.id] = p.x
	return out

## Pass 125: the proof that the crowd's compiled loops (native/, EnemyManager._nat) play a run exactly as the script does: a
## run recorded with the script (mode=record native=0, the bot playing) replayed through the library (mode=replay native=1):
## every checkpoint (the crowd's checksum, the hero, the dice, the kills) must be equal, and in both directions. This is
## _p114_REPLAY_proof.gd with the switch; it also prints whether the library ran and how much of the crowd it took.
##   record: bash tools/godot.sh --headless --path game --script res://tools/_p125_NATIVE_proof.gd -- mode=record native=0 out=<f> hero=drifter stage=1 seed=7 limit=300 check=1 [god=1] [give=...]
##   replay: bash tools/godot.sh --headless --fixed-fps 64 --path game --script res://tools/_p125_NATIVE_proof.gd -- mode=replay native=1 file=<f> out=<report.json>
extends "res://tools/_p114_REPLAY_proof.gd"


func _say_native() -> void:
	var g = current_scene
	var em = g.get("enemies") if g != null else null
	if em == null:
		_say("native: no crowd")
		return
	_say("native: on %s, class there %s; counts plain %s" % [str(em.native_on()), str(ClassDB.class_exists(&"CrowdCore")), str(em.native_counts())])
	# pass 126 (lane BOSS): whether a Dust Bowl fight in the run really played the whirl and the blizzard
	var wh = em.get("whirls")
	if wh != null:
		_say("whirls: started %d ended %d cut %d lifted %d tosses %d saved %d" % [wh.started, wh.ended, wh.cut, wh.lifted, wh.tosses, wh.saved])
	var pt = em.get("patterns")
	if pt != null:
		_say("patterns: started %d ended %d fired %d hits %d" % [pt.started, pt.ended, pt.fired, pt.hits])


func _end_report(why: String) -> void:
	_say_native()
	super._end_report(why)


func _store_recording(rr: Node) -> void:
	_say_native()
	super._store_recording(rr)

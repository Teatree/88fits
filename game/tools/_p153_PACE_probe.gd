## Pass 153: Endless's pacing and chests, played: the Endless probe (tools/_p150_ENDLESS_probe.gd: the kite from Endless's
## first second, the outlaw never dies) with the stage's kill-chest rate set as a stage run would have left it
## (`chests_per_min`, over `stage_secs`), so WaveDirector.kill_chest_ok governs Endless's chests; at the end the chests
## Endless let through and held back. The spawn lines ("spawn84 endless <id> <n> <Endless second>") are what
## tools/dl/p153/ENDLESS/pace_log.py reads for the pacing (a spawn moment's size, the creatures a 2 s window, the quiet).
##   bash tools/godot.sh --headless --fixed-fps 60 --path D:/_projects/88fits/game --log-file <f> \
##       --script res://tools/_p153_PACE_probe.gd -- stage=0 t0=420 secs=240 level=30 build=b2 hero=drifter seed=11 chests_per_min=0.75
extends "res://tools/_p150_ENDLESS_probe.gd"

var _cpm := 0.75
var _stage_secs := 600.0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2 and kv[0] == "chests_per_min":
			_cpm = float(kv[1])
		elif kv.size() == 2 and kv[0] == "stage_secs":
			_stage_secs = float(kv[1])
	super._init()


func _go_endless() -> void:
	var d = _game.director
	d._stage_secs = _stage_secs
	d._stage_chests = int(round(_cpm * _stage_secs / 60.0))
	super._go_endless()
	print("pace: the stage's kill chests set to %d over %.0f s (%.2f a minute)" % [d._stage_chests, _stage_secs, _cpm])


func _report(ran: float) -> void:
	super._report(ran)
	var r: Dictionary = _game.director.chest_rate()
	print("pace: Endless %.0f s: kill chests dropped %d, held back %d (%.2f a minute; the stage's %.2f, x share %.2f)" % [ran,
		int(r["dropped"]), int(r["held"]), 60.0 * float(r["dropped"]) / maxf(ran, 1.0), float(r["per_minute"]),
		_game.director.timeline.endless_value("chest_share", _stage)])

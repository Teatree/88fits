## Pass 102 lane STEADY: what Performance.TIME_PROCESS / TIME_PHYSICS_PROCESS report in 4.7 (per frame or per second; max or last).
extends SceneTree

var _f := 0
var _phys_busy := 4
var _proc_busy := 2
var _vals: Array = []

func _initialize() -> void:
	physics_frame.connect(_on_phys)

func _spin(ms: float) -> void:
	var t := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t < int(ms * 1000.0):
		pass

func _on_phys() -> void:
	# every 30th physics step is a slow one
	_spin(_phys_busy * (5 if Engine.get_physics_frames() % 30 == 0 else 1))

func _process(_delta: float) -> bool:
	_f += 1
	_spin(_proc_busy * (4 if _f % 25 == 0 else 1))
	_vals.append([_f, snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01), snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01)])
	if _f >= 200:
		var s := ""
		for i in range(0, _vals.size(), 7):
			s += str(_vals[i]) + " "
		print(s)
		return true
	return false

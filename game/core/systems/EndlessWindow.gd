## Pass 150 (lane ENDLESS): a stage's Endless window as one Endless plays it. Garry (2026-11-14): "I'd want the Endless
## Mode to really feel endless, different enemies (randomized), some colour variation, Elites, Specials, Elitted normal
## enemies, etc. ... Give me tools in the Level Editor Timeline Tab which would allow me to set a kind of a pace with
## deciding how they would spawn ... For Endless Mode specifically I want similar type of Controls as the Boss Fights
## has." The stage entry's `endless_window` block (WaveTimeline.endless_window: length, max_count, max_count_growth,
## roster) holds spawn rows with the roster's keys, every time on ENDLESS'S clock. WaveDirector hands Endless to this from
## its start (start_endless -> begin) until the run ends (stop); while it is active only these rows spawn (the old Endless
## waves and fill rest; the specials' clock never runs in Endless). Every rule is BossFightWindow's (the cycle that loops,
## the continuous draw under max_count, the waves and once rows, "roster", the elite rows, from_cycle / until_cycle, the
## variations), with these differences:
##   - nothing holds it (no boss, no bullet heaven);
##   - pass 153: it may pulse (WaveTimeline.endless_window_pulse: quiet stretches, a share of the drawn rows a pulse, a
##     bigger burst; BossFightWindow.quiet / _pulse_begin);
##   - max_count grows by `max_count_growth` bodies each later cycle (cycle c, 0-based), never past the hard cap;
##   - the numbers: each row's creatures are fixed from the stage's end (the run clock stands there) and the hero's level,
##     then times Endless's growth step (WaveDirector.source_for: hp, atk afresh at every Endless wave, `endless.every`
##     seconds), so a row that keeps coming keeps getting tougher; the speed step reaches every creature
##     (EnemyManager.set_endless_speed) as before.
class_name EndlessWindow
extends BossFightWindow

## max_count as the block has it (cycle 0), and the bodies it gains a cycle
var base_max := 100
var growth := 0.0


func _init() -> void:
	log_kind = "endless"


## Endless of stage `p_stage` begins (the portal's countdown ran out): true when the stage has a window (it then plays
## it), false (inactive) without one, so the director keeps the old Endless.
func begin(d, p_stage: int) -> bool:
	dir = d
	active = false
	_st.clear()
	_roll.clear()
	_draw_left.clear()
	came_by = {}
	came_total = 0
	cycles = 0
	cycle = -1
	clock = 0.0
	if d == null or d.timeline == null:
		return false
	var tl: WaveTimeline = d.timeline
	if not tl.has_endless_window(p_stage):
		return false
	stage = p_stage
	length = tl.endless_window_length(stage)
	base_max = tl.endless_window_max_count(stage)
	growth = tl.endless_window_growth(stage)
	max_count = base_max
	rows = tl.endless_window_rows(stage)
	t0_run = tl.stage_end(stage)
	# pass 153: the pulse (quiet stretches, a share of the drawn rows a pulse, a bigger burst)
	var pz := tl.endless_window_pulse(stage)
	pulse_on = float(pz["on"]) if bool(pz["active"]) else 0.0
	pulse_off = float(pz["off"]) if bool(pz["active"]) else 0.0
	pulse_rows = float(pz["rows"])
	pulse_burst = float(pz["burst"])
	active = true
	_new_cycle(0)
	return true


## The run's key of window row `r` at index `k`: "endless<stage>:<id>#<k>".
func key_of(r: Dictionary, k: int) -> String:
	return "endless%d:%s#%d" % [stage, str(r.get("id", "")), k]


## Nothing holds Endless's window.
func held() -> bool:
	return false


## A new cycle: BossFightWindow's, then max_count grown for it.
func _new_cycle(c: int) -> void:
	super(c)
	max_count = max_count_at(c)


## The window's max_count in cycle `c` (0-based): base + growth x c, at most the hard cap; -1 stays -1.
func max_count_at(c: int) -> int:
	if base_max < 0:
		return -1
	var m := base_max + int(floor(growth * float(maxi(c, 0))))
	if dir != null and dir.timeline != null:
		m = mini(m, int(dir.timeline.hard_cap))
	return m

## Pass 114 (lane REPLAY): the run's rule dice. Every roll that can change a run (a crit, a drop, a spawn's spot, an
## AI's choice, a projectile's spread) comes from `Dice.r`, seeded from the run's seed (Run.run_seed, set by
## Run.seed_dice at every run's start), or from a system's own RandomNumberGenerator seeded through `seed_rng`. The
## global randf()/randi()/randf_range()/pick_random()/shuffle() stream is the LOOKS' stream (particles, sound pitch,
## damage-number jitter, UI flourishes, whatever the engine itself rolls): no rule reads it, so a look, a sound or a
## skipped drawing can never shift a rule's roll, and a recorded run replays exactly (core/systems/RunReplay.gd).
## Names no autoload (tools and tests compile it before the autoloads exist).
class_name Dice
extends RefCounted

## The rule dice of the run now playing (re-seeded at every run's start).
static var r := RandomNumberGenerator.new()
## The seed the dice were last seeded from (0 = random, before any run).
static var run_seed := 0


## Seeds the rule dice from a run's seed (0 = random).
static func reseed(s: int) -> void:
	run_seed = s
	if s == 0:
		r.randomize()
	else:
		r.seed = hash([s, "rules"])


## A system's own dice seeded from the run's seed and its own salt, so its rolls never move another system's; random
## when no run seed is set (a test, the title).
static func seed_rng(rng: RandomNumberGenerator, salt: String) -> void:
	if rng == null:
		return
	if run_seed == 0:
		rng.randomize()
	else:
		rng.seed = hash([run_seed, salt])


## A fresh RandomNumberGenerator seeded as seed_rng does.
static func rng_for(salt: String) -> RandomNumberGenerator:
	var g := RandomNumberGenerator.new()
	seed_rng(g, salt)
	return g


## One element of `a` from the rule dice (null when empty): the rule-side Array.pick_random().
static func pick(a: Array):
	if a.is_empty():
		return null
	return a[r.randi() % a.size()]


## `a` shuffled in place from the rule dice (Fisher-Yates): the rule-side Array.shuffle().
static func shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := r.randi() % (i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t

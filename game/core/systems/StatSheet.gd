## A bag of named stats with a base value and a list of Effects, each tagged with its source.
## final = (base + Σ add) × Π (1 + mul), with "set" replacing the base. Keeps sources so the
## pause screen can show every stat's breakdown.
class_name StatSheet
extends RefCounted

## Known player stats with defaults. Weapons use their own keys from WeaponDef.base.
const PLAYER_DEFAULTS := {
	"max_hp": 100.0, "armor": 0.0, "regen": 0.0, "move_speed": 3.6, "might": 1.0, "cooldown": 1.0,
	"area": 1.0, "projectile_speed": 1.0, "duration": 1.0, "amount": 0.0, "magnet": 1.5, "luck": 0.0,
	"greed": 1.0, "revives": 0.0, "rerolls": 0.0, "skips": 0.0, "banishes": 0.0, "turn_rate": 180.0,
}

var base: Dictionary = {}
## Array of {"effect": Effect, "source": String}
var entries: Array = []


func set_base(stat: String, v: float) -> void:
	base[stat] = v


func set_bases(d: Dictionary) -> void:
	for k in d.keys():
		base[str(k)] = float(d[k])


func add_effect(e: Effect, source: String = "") -> void:
	if e == null or e.stat == "":
		return
	entries.append({"effect": e, "source": source})


func add_effects(list: Array, source: String = "") -> void:
	for e in list:
		if e is Effect:
			add_effect(e, source)


func remove_source(source: String) -> void:
	var keep: Array = []
	for en in entries:
		if en["source"] != source:
			keep.append(en)
	entries = keep


func clear_effects() -> void:
	entries.clear()


func has_stat(stat: String) -> bool:
	if base.has(stat):
		return true
	for en in entries:
		if en["effect"].stat == stat:
			return true
	return false


func get_stat(stat: String, default: float = 0.0) -> float:
	var b: float = float(base.get(stat, default))
	var adds := 0.0
	var mul := 1.0
	for en in entries:
		var e: Effect = en["effect"]
		if e.stat != stat:
			continue
		match e.op:
			"add":
				adds += e.value
			"mul":
				mul *= (1.0 + e.value)
			"set":
				b = e.value
	return (b + adds) * mul


func get_int(stat: String, default: int = 0) -> int:
	return int(round(get_stat(stat, float(default))))


func stats() -> Array:
	## Every stat name present, base keys first then any effect-only keys.
	var out: Array = base.keys()
	for en in entries:
		var s: String = en["effect"].stat
		if not out.has(s):
			out.append(s)
	return out


func breakdown(stat: String) -> Array:
	## Rows for the Stats tab: [{"source": "base", "text": "5.0"}, {"source": "Dad", "text": "+20%"}, ...]
	var rows: Array = [{"source": "base", "text": TextGen.format_value(stat, float(base.get(stat, 0.0)))}]
	for en in entries:
		var e: Effect = en["effect"]
		if e.stat == stat:
			rows.append({"source": en["source"], "text": TextGen.describe_effect(e, false)})
	rows.append({"source": "total", "text": TextGen.format_value(stat, get_stat(stat))})
	return rows


func duplicate_sheet() -> StatSheet:
	var s := StatSheet.new()
	s.base = base.duplicate()
	s.entries = entries.duplicate()
	return s

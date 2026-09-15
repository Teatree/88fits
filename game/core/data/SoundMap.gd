## Binds sound ids to streams and mixing rules. One row per id from design bible section 16.
class_name SoundMap
extends Resource

## id -> {"file": String, "stream": AudioStream, "category": String, "voices": int, "pitch_spread": float, "volume_db": float, "loop": bool}
@export var entries: Dictionary = {}


func has_sound(id: String) -> bool:
	return entries.has(id)


func entry(id: String) -> Dictionary:
	return entries.get(id, {})

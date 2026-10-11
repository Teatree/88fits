## A map: an arena scene, a wave timeline, enemy skins per archetype, a boss, and an unlock quest.
class_name MapDef
extends ContentDef

@export var scene: PackedScene
@export var scene_file: String = ""
@export var timeline: WaveTimeline
@export var timeline_file: String = ""
## archetype -> enemy id, e.g. {"walker": "goblin", "swarmer": "fire_ant", ...}
@export var skins: Dictionary = {}
## Pass 67: how this map's light wants the 3D weapon models drawn: {value, saturation, glow}. Every lit material of a
## weapon's visual is graded value x `value`, saturation x `saturation` (WeaponBehavior.grade_materials) and the companion
## glow emits at `glow`; a missing key takes WeaponBehavior.GRADE / GLOW, a weapon's `params.grade` wins over the block.
@export var weapon_grade: Dictionary = {}
@export var boss: String = ""
@export var unlock_quest: String = ""
## Sound ids for music layers and ambient
@export var music: Dictionary = {"ambient": "wd_ambient", "run": ["mu_run_1", "mu_run_2", "mu_run_3"], "boss": "mu_boss"}


func kind() -> String:
	return "map"

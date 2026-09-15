## First scene. Waits for autoloads, then goes to the title screen.
extends Control

const TITLE := "res://ui/TitleScreen.tscn"


func _ready() -> void:
	await get_tree().process_frame
	if not Registry.problems.is_empty():
		for p in Registry.problems:
			push_warning("Content: " + str(p))
	if ResourceLoader.exists(TITLE):
		get_tree().change_scene_to_file(TITLE)
	else:
		print("Boot: no title screen yet; registry loaded %d weapons" % Registry.weapons.size())

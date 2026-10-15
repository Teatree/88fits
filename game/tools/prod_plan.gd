## Pass 81 (lane PROD): the production build's keep/drop plan (tools/prod_reach.gd) as JSON for tools/prod_prune.py.
## Run: godot --headless --path <project> --script res://tools/prod_plan.gd -- out=<file.json>
## Prints "prod_plan: OK keep N drop M -> <file>"; exit 1 when the Registry has problems or the file cannot be written.
extends SceneTree


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var out := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.trim_prefix("out=")
	var reg: Node = root.get_node("Registry")
	var reach = load("res://tools/prod_reach.gd")
	var plan: Dictionary = reach.plan(reg)
	plan["registry_problems"] = (reg.get("problems") as Array).duplicate()
	plan["version"] = str(ProjectSettings.get_setting("application/config/version", ""))
	if out == "":
		print(JSON.stringify(plan, "  "))
	else:
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f == null:
			push_error("prod_plan: cannot write %s" % out)
			quit(1)
			return
		f.store_string(JSON.stringify(plan, "  ", true))
		f.close()
	print("prod_plan: OK keep %d drop %d looks %d pins %d registry problems %d -> %s" % [plan["counts"]["keep"],
		plan["counts"]["drop"], (plan["looks"] as Dictionary).size(), (plan["pins"] as Array).size(),
		(plan["registry_problems"] as Array).size(), out])
	quit(0)

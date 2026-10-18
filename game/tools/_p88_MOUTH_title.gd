## Pass 88 lane MOUTH scratch capture: the live title's companion frame by frame over a full turn round the hero (May
## and her Big Mouth by default), with a per-frame log (orbit, place, rotation, the drawn scale, its point on the
## screen) to find a stutter. Windowed, fixed fps, sandboxed save, a watchdog:
##   bash tools/godot.sh --audio-driver Dummy --fixed-fps 60 --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --script res://tools/_p88_MOUTH_title.gd -- out=<dir> [hero=may] [frames=300] [step=3] [crop=520] [tag=t]
extends SceneTree

const WATCHDOG_S := 150.0

var _out := "user://p88_mouth_title"
var _hero := "may"
var _frames := 300
var _step := 3
var _crop := 520
var _tag := "t"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("hero="):
			_hero = a.substr(5)
		elif a.begins_with("frames="):
			_frames = int(a.substr(7))
		elif a.begins_with("step="):
			_step = maxi(int(a.substr(5)), 1)
		elif a.begins_with("crop="):
			_crop = int(a.substr(5))
		elif a.begins_with("tag="):
			_tag = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(WATCHDOG_S, true, false, true).timeout.connect(func() -> void:
		push_error("p88 mouth title: watchdog")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _main() -> void:
	var save = root.get_node("Save")
	var settings = root.get_node("Settings")
	save.begin_sandbox()
	settings.menu_style = "live"
	save.data["gold"] = 1200
	save.data["last_character"] = _hero
	save.data["heroes_owned"] = [_hero]
	change_scene_to_file("res://ui/TitleScreen.tscn")
	await _wait(2.0)
	var t = current_scene
	var stg = t.get_node_or_null("TitleStage") if t else null
	if stg == null or stg.hero == null:
		print("p88 mouth title: no stage or hero")
		save.end_sandbox()
		quit(1)
		return
	for c in t.get_children():
		if c is CanvasItem and c.name != "TitleStage":
			(c as CanvasItem).visible = false
	var actor = stg.hero
	var fam: Node3D = actor.familiar
	if fam == null:
		print("p88 mouth title: no companion")
		save.end_sandbox()
		quit(1)
		return
	var log := FileAccess.open(_out.path_join(_tag + "_frames.txt"), FileAccess.WRITE)
	var cam: Camera3D = stg.camera
	for fr in range(_frames):
		await process_frame
		var img: Image = null
		if fr % _step == 0:
			img = root.get_viewport().get_texture().get_image()
		# the hero's feet on the screen (the stage's viewport fills the window)
		var vp_size: Vector2 = stg.viewport.size
		var feet_sp: Vector2 = cam.unproject_position(actor.global_position + Vector3(0, 0.9, 0))
		var sp: Vector2 = cam.unproject_position(fam.global_position)
		var mouth: Node3D = fam.get_node_or_null("Mouth")
		var fwd := -(mouth.global_transform.basis.z if mouth else fam.global_transform.basis.z).normalized()
		log.store_line("f%03d orbit=%.3f fam_pos=%s at=%s scale=%.3f rot=%s sp=%.1f,%.1f fwd=%.2f,%.2f,%.2f" % [fr, float(actor.get("_orbit")), str(actor.fam_pos), str(fam.global_position), fam.scale.x, str(fam.rotation), sp.x, sp.y, fwd.x, fwd.y, fwd.z])
		if img:
			var k := Vector2(float(img.get_width()) / vp_size.x, float(img.get_height()) / vp_size.y) if vp_size.x > 0.0 else Vector2.ONE
			var cx := int(feet_sp.x * k.x)
			var cy := int(feet_sp.y * k.y)
			var c := mini(_crop, mini(img.get_width(), img.get_height()))
			var x := clampi(cx - c / 2, 0, img.get_width() - c)
			var y := clampi(cy - c / 2, 0, img.get_height() - c)
			img.get_region(Rect2i(x, y, c, c)).save_png(_out.path_join("%s_f%03d.png" % [_tag, fr]))
	log.close()
	print("p88 mouth title: done -> ", _out)
	save.end_sandbox()
	quit(0)

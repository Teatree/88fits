## Pass 115 (lane BOSS): the barriers' look bench. A bare scene (sand, the map's sun, sky light and haze, the game's camera
## angle) with one barrier of each look round a point, captured at set moments of its rise, standing and its fall, from the
## game's camera and from a closer three-quarter view. Windowed, bounded (a frame cap and a watchdog), no save touched.
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game
##        --script res://tools/_p115_BOSS_lab.gd -- out=<dir> [looks=tumbleweed_fence,cactus_fence,iron_fence]
##        [view=game|close|both] [radius=10] [tint=night|blood] [at=r0.3,r0.6,r1.6,f0.35,f0.8]
## `at`: r<s> = s seconds into the rise (standing after rise_s + spread_s), f<s> = s seconds into the fall.
extends SceneTree

const WATCHDOG_S := 120.0
const FRAME_CAP := 4000
const ATTACKS := {"tumbleweed_fence": "royal_dust_devil", "cactus_fence": "venom_monsoon", "iron_fence": "hellbrand_mandala"}

var A: Dictionary = {}
var _frames := 0
var _ended := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=", true, 1)
		A[kv[0]] = kv[1] if kv.size() > 1 else "1"
	create_timer(float(A.get("watchdog", WATCHDOG_S)), true, false, true).timeout.connect(_bail.bind("watchdog"))
	process_frame.connect(_count)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _count() -> void:
	_frames += 1
	if _frames > FRAME_CAP:
		_bail("frame cap")


func _log(s: String) -> void:
	print("p115lab: " + s)


func _bail(why: String) -> void:
	_log("stopped: " + why)
	_finish(2)


func _finish(code: int) -> void:
	if _ended:
		return
	_ended = true
	quit(code)


func _wait(n: int) -> void:
	for k in range(n):
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	_log("saved " + path)


func _main() -> void:
	var reg = root.get_node("Registry")
	var out := str(A.get("out", "D:/_projects/88fits/tools/dl/p115/BOSS/lab"))
	var looks := str(A.get("looks", "tumbleweed_fence,cactus_fence,iron_fence")).split(",")
	var view := str(A.get("view", "both"))
	var r := float(A.get("radius", 10.0))
	var world := Node3D.new()
	root.add_child(world)
	# the map's light (RedCanyon._build_sky)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.89, 0.62, 0.40)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.95, 0.80, 0.66)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.93, 0.66, 0.42)
	env.fog_density = 0.004
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.85, 0.65)
	sun.light_energy = 1.3
	sun.rotation_degrees = Vector3(-42, 140, 0)
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300, 300)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	var tint := str(A.get("tint", ""))
	gm.albedo_color = Color(0.93, 0.80, 0.56) if tint == "" else (Color(0.42, 0.5, 0.7) if tint == "night" else Color(0.62, 0.3, 0.22))
	if ResourceLoader.exists("res://art/env/sand.png") and tint == "":
		gm.albedo_texture = load("res://art/env/sand.png")
		gm.uv1_scale = Vector3(40, 40, 40)
		gm.albedo_color = Color(1, 1, 1)
	ground.material_override = gm
	world.add_child(ground)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	# a stand-in hero 3 m inside the ring's south side (a capsule the hero's size)
	var hero := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.8
	hero.mesh = cap
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.3, 0.4, 0.75)
	hero.material_override = hm
	world.add_child(hero)
	var bscript = load("res://core/systems/BossBarrier.gd")
	var ats := str(A.get("at", "r0.3,r0.6,r1.6,f0.35,f0.8")).split(",")
	for lk in looks:
		var cdef = reg.boss_attack(str(ATTACKS.get(lk, "royal_dust_devil")))
		if cdef == null:
			continue
		var c2 = cdef.duplicate()
		c2.barrier = (cdef.barrier as Dictionary).duplicate()
		c2.barrier["look"] = lk
		var focus := Vector3(0, 0, r - 2.5)
		hero.position = focus + Vector3(0, 0.9, 0)
		var b: Node3D = bscript.new()
		world.add_child(b)
		b.call("setup", null, c2, Vector3.ZERO, r, focus)
		b.set_process(false)
		_log("%s: %d stretches, %d pieces, %d MultiMeshes" % [lk, int(b.get("stretches")), int(b.get("pieces")), int(b.get("chunks"))])
		for vw in (["game", "close"] if view == "both" else [view]):
			if vw == "game":
				var p := deg_to_rad(48.0)
				cam.fov = 55.0
				cam.position = focus + Vector3(0, sin(p), cos(p)) * 22.0
				cam.look_at(focus, Vector3.UP)
			else:
				cam.fov = 40.0
				cam.position = focus + Vector3(4.5, 3.2, 7.5)
				cam.look_at(focus + Vector3(0, 0.6, 2.5), Vector3.UP)
			for at in ats:
				var ph := at.substr(0, 1)
				var s := float(at.substr(1))
				if ph == "r":
					b.set("t", s)
					b.set("fall_t", -1.0)
				else:
					b.set("t", 10.0)
					b.set("fall_t", s)
				b.call("_process", 0.0)
				await _wait(3)
				await _shot("%s/%s_%s_%s%s.png" % [out, lk, vw, "tint_" + tint + "_" if tint != "" else "", at])
		b.queue_free()
		await _wait(2)
	_finish(0)

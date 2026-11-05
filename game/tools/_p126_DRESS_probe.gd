## Pass 126 (lane DRESS): what the dressing's dice give over many map seeds, printed as one table: the line's poles and bare
## spans, the cart and its land, the graves, what a build costs. Headless:
##   bash tools/godot.sh --headless --path D:/_projects/88fits/game --log-file <abs> --script res://tools/_p126_DRESS_probe.gd -- seeds=60
## Touches no save. A watchdog quits it after 400 s.
extends SceneTree


func _initialize() -> void:
	create_timer(400.0, true, false, true).timeout.connect(func() -> void:
		push_error("probe: watchdog")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _main() -> void:
	var n := 60
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seeds="):
			n = int(a.substr(6))
	var run = root.get_node("Run")
	var reg = root.get_node("Registry")
	var def = reg.call("map", "red_canyon")
	var keep_seed: int = run.map_seed
	var keep_map = run.map
	run.map = def
	var totals := {"poles": 0, "spots": 0, "missing": 0, "snapped": 0, "leaning": 0, "spans": 0, "wired": 0, "carts": 0, "wheels": 0, "sites": 0, "crosses": 0, "sticks": 0, "lumps": 0, "dangles": 0, "fallen": 0}
	var flats: Array = []
	var flat_any: Array = []
	var spots_all: Array = []
	var ms := 0
	var tris := 0
	var turn_max := 0.0
	var span_lo := 99.0
	var span_hi := 0.0
	for k in n:
		var s := 1000 + k * 37
		run.map_seed = s
		var t0 := Time.get_ticks_msec()
		var m: Node3D = (def.scene as PackedScene).instantiate()
		root.add_child(m)
		ms += Time.get_ticks_msec() - t0
		var d = m.get("dressing")
		var line = m.get_node_or_null("TelephoneLine")
		if line:
			var pts := PackedVector2Array()
			for p: Dictionary in line.poles:
				totals["spots"] += 1
				pts.append(p["pos"])
				match str(p["state"]):
					"missing":
						totals["missing"] += 1
					"snapped":
						totals["snapped"] += 1
						if bool(p["fallen"]):
							totals["fallen"] += 1
					"leaning":
						totals["leaning"] += 1
				if p["state"] != "missing":
					totals["poles"] += 1
			turn_max = maxf(turn_max, line.sharpest_turn(pts))
			for j in range(pts.size() - 1):
				var len_j := pts[j].distance_to(pts[j + 1])
				span_lo = minf(span_lo, len_j)
				span_hi = maxf(span_hi, len_j)
			for sp: Dictionary in line.spans:
				totals["spans"] += 1
				if bool(sp["wired"]):
					totals["wired"] += 1
			totals["dangles"] += line.dangles.size()
		if not d.cart.is_empty():
			totals["carts"] += 1
			totals["wheels"] += (d.cart["wheels"] as Array).size()
			flats.append(float(d.cart["flat"]))
		for g: Dictionary in d.graves:
			totals["sites"] += 1
			if (g["crosses"] as Array).size() > 1:
				totals["lumps"] += 1
			for c: Dictionary in g["crosses"]:
				totals["crosses"] += 1
				if bool(c["stick"]):
					totals["sticks"] += 1
		# what the land offers: how flat 200 open spots are with the cart's own rules (the flats, the river, the lakes, the wall)
		var best := 99.0
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		for j in 200:
			var a := rng.randf() * TAU
			var r := rng.randf_range(20.0, 59.0)
			var pt := Vector2(cos(a) * r, sin(a) * r)
			if pt.distance_to(Vector2(0, 8)) < 20.8 or float(m.call("_lake_edge", pt)) < 3.0 or float(m.call("_river_dist", pt)) < 5.8:
				continue
			var fl := float(d.flatness(pt, 5.0))
			spots_all.append(fl)
			best = minf(best, fl)
		flat_any.append(best)
		var dm = d.get_node_or_null("DressMesh")
		if dm:
			tris = maxi(tris, (dm.mesh as ArrayMesh).surface_get_array_len(0))
		m.free()
		await process_frame
	run.map_seed = keep_seed
	run.map = keep_map
	flats.sort()
	flat_any.sort()
	print("probe: seeds ", n, " build ms each ", ms / max(n, 1), " max verts ", tris)
	print("probe: ", totals)
	print("probe: bare share ", 1.0 - float(totals["wired"]) / maxf(float(totals["spans"]), 1.0), " turn max ", turn_max, " span ", span_lo, "..", span_hi)
	if not flats.is_empty():
		print("probe: cart flat median ", flats[flats.size() / 2], " max ", flats[flats.size() - 1])
	print("probe: land's flattest spot median ", flat_any[flat_any.size() / 2], " worst ", flat_any[flat_any.size() - 1])
	spots_all.sort()
	var q := func(f: float) -> float: return float(spots_all[int(f * float(spots_all.size() - 1))])
	print("probe: open spots' rise and fall p5 %.2f p10 %.2f p25 %.2f p50 %.2f p75 %.2f p95 %.2f" % [q.call(0.05), q.call(0.1), q.call(0.25), q.call(0.5), q.call(0.75), q.call(0.95)])
	quit(0)

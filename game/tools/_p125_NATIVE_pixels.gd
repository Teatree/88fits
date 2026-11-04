## Pass 125: the proof that the crowd's compiled draw (EnemyManager._render_native, native/src/crowd_render.cpp) puts the same
## pixels on the screen as the script's. _p101_CROWD_pixels.gd's busy scenes (300 of stage 3's mix, the far zooms, big creatures,
## Elites and bosses across every edge, walking in, corpses thrown, rising out of the sand, the camera panning); at each capture
## the frame is drawn three times with no time passing: by the script, by the library, by the script again (the control).
##   bash tools/godot.sh --audio-driver Dummy --resolution 504x1122 --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/_p125_NATIVE_pixels.gd -- out=<dir>
## Writes <out>/pixels.txt and PNGs of the first capture of each scene and of any that differs. Exit 0 when none differed.
extends "res://tools/_p101_CROWD_pixels.gd"


func _capture(scene: String) -> void:
	var em = _game.enemies
	var cam = _game.camera
	if cam.has_method("_update"):
		cam._update(root.get_process_delta_time())
	var nat = em._nat
	var alive := 0
	for i in range(_C["MAX"]):
		if em.alive[i] == 1 and em.hidden[i] == 0 and em.drawn_vis[i] == 1:
			alive += 1
	# (each draw's shadow cache last draped at another moment: both drape afresh here)
	em._shc_key.fill(-1.0)
	nat.shadow_cache_clear()
	em._nat = null
	em._render()
	RenderingServer.force_draw(false, 0.0)
	var a: Image = root.get_texture().get_image()
	em._nat = nat
	em._render()
	RenderingServer.force_draw(false, 0.0)
	var b: Image = root.get_texture().get_image()
	em._nat = null
	em._render()
	RenderingServer.force_draw(false, 0.0)
	var a2: Image = root.get_texture().get_image()
	em._nat = nat
	em._render()
	_captures += 1
	var diff := _count_diff(a, b) if a.get_data() != b.get_data() else 0
	# overlapping shadows blend in another order when the script draws a few of them after the rest: 1/255 of a channel at most,
	# so only more than that counts as a difference
	var big := _count_big(a, b) if diff > 0 else 0
	var ctrl := _count_diff(a, a2) if a.get_data() != a2.get_data() else 0
	var tag := "%02d_%s_%03d" % [_si, scene, _sf]
	_log("%s: drawn %d | native %s | pixels differing at all %d, by more than 1/255 %d | control %d" % [tag, alive, str(nat != null), diff, big, ctrl])
	if big > 0:
		_fails += 1
		a.save_png(_out + "/%s_script.png" % tag)
		b.save_png(_out + "/%s_native.png" % tag)
		_diff_mask(a, b).save_png(_out + "/%s_diff.png" % tag)
	if ctrl > 0:
		_ctrl_fails += 1
	if _sf == int(_scenes[_si][3]):
		a.save_png(_out + "/%s_script.png" % tag)
		b.save_png(_out + "/%s_native.png" % tag)


func _count_big(a: Image, b: Image) -> int:
	var da := a.get_data()
	var db := b.get_data()
	var step := da.size() / (a.get_width() * a.get_height())
	var n := 0
	var k := 0
	while k < da.size():
		if absi(da[k] - db[k]) > 1 or absi(da[k + 1] - db[k + 1]) > 1 or absi(da[k + 2] - db[k + 2]) > 1:
			n += 1
		k += step
	return n

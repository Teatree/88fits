## Pass 114 (lane REPLAY): a recording's blobs re-packed with each compressor, sizes printed (deflate/gzip vs zstd).
## Tools only.   bash tools/godot.sh --headless --path game --script res://tools/_p114_REPLAY_sizes.gd -- file=<replay.json>
extends SceneTree


func _init() -> void:
	var file := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("file="):
			file = a.substr(5)
	var d = JSON.parse_string(FileAccess.get_file_as_string(file))
	for k in ["frames", "stick", "hero_steps", "track"]:
		var s := str(d.get(k, ""))
		var i := s.rfind(":")
		var raw := Marshalls.base64_to_raw(s.substr(0, i)).decompress(int(s.substr(i + 1)), FileAccess.COMPRESSION_GZIP)
		var gz := raw.compress(FileAccess.COMPRESSION_GZIP)
		var zs := raw.compress(FileAccess.COMPRESSION_ZSTD)
		var df := raw.compress(FileAccess.COMPRESSION_DEFLATE)
		print("sizes: %s raw %d gzip %d deflate %d zstd %d" % [k, raw.size(), gz.size(), df.size(), zs.size()])
	quit(0)

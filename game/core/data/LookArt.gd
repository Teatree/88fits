## Pass 101 (lane LOOKS; Garry's item 6: "load only the looks that will appear"): the big pictures of the looks, the
## heroes' and creatures' sprite strips, load the first time something asks for them, never with the content. Every
## look stays listed everywhere (its code, note, chip and icon live in the def); only its strip waits here as a path.
## Before pass 101 the Registry's .tres files named every strip of every look, so boot put 856 pictures, ~2.3 GB at 4 bytes
## a pixel, into the GPU (tools/dl/p100/PERF/vram_a.txt).
##
## What is kept: the run's own set, pinned (RunLooks.prepare: every creature its stage can bring in the look it plays,
## the hero's look, the arena's and a tool's launch picks) until the next run pins its own; and, beyond it, the strips
## asked for most recently up to KEEP_MB (the title's heroes swiped past, the arena's picks), the oldest let go first. A
## strip let go here stays alive as long as a material still draws it (Godot's resource cache hands the same texture back
## to the next ask), so letting go never changes what is on screen; it only lets an unused one be freed.
class_name LookArt
extends RefCounted

## The unpinned strips kept after their last ask, in MB at 4 bytes a pixel (a hero strip is 46.5 MB, a creature's
## 3-27 MB): the title's carousel or the arena's chips come back without a reload for the last few.
const KEEP_MB := 160.0

## path -> Texture2D, the most recently asked last
static var _held: Dictionary = {}
## path -> true: the run's set, never let go until the next pin_only
static var _pinned: Dictionary = {}
## disk loads made here since boot (the tests count them)
static var loads := 0


## The strip at `path` (a res:// path), loaded on the first ask and kept (see the header); null for "" or a missing file.
static func tex(path: String) -> Texture2D:
	if path == "":
		return null
	var hit = _held.get(path)
	if hit != null:
		# the most recently asked last
		_held.erase(path)
		_held[path] = hit
		return hit
	if not ResourceLoader.exists(path):
		return null
	var t = ResourceLoader.load(path)
	if not (t is Texture2D):
		return null
	loads += 1
	_held[path] = t
	_trim()
	return t


## Whether the strip at `path` is held here now (loaded and not let go).
static func is_held(path: String) -> bool:
	return _held.has(path)


## Whether the strip at `path` is in the pinned set.
static func is_pinned(path: String) -> bool:
	return _pinned.has(path)


## The paths held now (tests, the probes).
static func held_paths() -> Array:
	return _held.keys()


## Pins exactly `paths` (loading each now, so nothing waits for its first appearance) and unpins every other, which
## then counts against KEEP_MB like any recent ask. Returns how many of them were loaded from disk now.
static func pin_only(paths: Array) -> int:
	var before := loads
	_pinned.clear()
	for p in paths:
		var s := str(p)
		if s == "":
			continue
		if tex(s) != null:
			_pinned[s] = true
	_trim()
	return loads - before


## Pins `path` too (loading it), keeping the rest of the pinned set: a pick mid-run that must not be let go.
static func pin(path: String) -> Texture2D:
	var t := tex(path)
	if t != null:
		_pinned[path] = true
	return t


## Lets go of every unpinned strip over KEEP_MB, the least recently asked first.
static func _trim() -> void:
	var budget := int(KEEP_MB * 1048576.0)
	var used := 0
	var keys := _held.keys()
	# newest first: they stay
	for k in range(keys.size() - 1, -1, -1):
		var p: String = keys[k]
		if _pinned.has(p):
			continue
		var t: Texture2D = _held[p]
		used += t.get_width() * t.get_height() * 4
		if used > budget:
			_held.erase(p)


## Lets go of everything held here (tests): what a material still draws stays alive in Godot's cache.
static func clear() -> void:
	_held.clear()
	_pinned.clear()


## A look entry's icon (pass 101): an entry holds its icon's res:// path (what JsonContent writes since pass 101, so an
## unplayed look's icon is never loaded with the content), or a texture (an old .tres, a stand-in). The path loads through
## Godot's own cache (icons are small: not held here); null for "", a missing file or anything else.
static func icon(v) -> Texture2D:
	if v is Texture2D:
		return v
	if v is String and str(v) != "" and ResourceLoader.exists(str(v)):
		var t = load(str(v))
		return t if t is Texture2D else null
	return null


## The res:// path of `file` in content folder `dir` ("" for ""; a res:// file stays as it is).
static func path_in(dir: String, file: String) -> String:
	if file == "":
		return ""
	return file if file.begins_with("res://") else dir + file

## The string table (pass 137, lane LOCKIT): every text a player reads that lives in code is a row of
## res://content/strings/en.json, a flat {key: text}; a content item's own words (`name`, `flavour`, a mutation's `text`, ...)
## stay in its JSON (one source of truth a string). Guide: docs/howto/texts_and_localization.html; rules for adding a text:
## .claude/skills/game-texts/SKILL.md.
##
##   Loc.t("ui.portal.extract")                                   -> "EXTRACT"
##   Loc.t("gen.weapon.shot.nearest", {"amount": "3", "range": "8"}) -> "Fires 3 shots at the nearest enemy within 8 m."
##
## A text's variables: `{name}` is the value handed in (numbers are formatted by the calling code, as strings, so the text
## never decides how a number looks); `{name?one:many}` is the first part when the value is exactly 1 (the number 1 or the
## string "1"), else the second, and either part may hold `{other}` variables; `{{` and `}}` are a literal brace.
## A missing key gives the key itself back, a missing variable leaves `{name}` in the text; both warn once (push_warning,
## and `warnings()` for the tests).
##
## Later languages: strings/<lang>.json with the same keys, each falling back to English (load_table(lang)); a content
## item's words translate under the key that mirrors their JSON field (`weapon.revolver.name`, `content()`).
##
## Static, no autoload named (tools compile this before the autoloads exist). Pass 129's lesson: no static `reload` on a
## class_name script (Script.reload); it is `load_table`.
class_name Loc
extends RefCounted

const DIR := "res://content/strings/"
const ENGLISH := "en"
## Where capture mode writes what it saw, from the repo root (the Level Editor's Strings tab shows these values beside each
## variable); samples_path() makes it absolute.
const SAMPLES_REL := "tools/dl/loc/samples.json"

static var _table: Dictionary = {}       # key -> text in the language played (English under it)
static var _loaded := false
static var _lang := ENGLISH
static var _parsed: Dictionary = {}      # template text -> its segments (a cache: TextGen runs for every card)
static var _warned: Dictionary = {}      # warning text -> true (each warns once)
static var _warnings: Array = []
## Capture mode (tools): every t() records its key's last variables and rendered text.
static var capture := false
static var _samples: Dictionary = {}


## (Re)reads the table: English, then `lang` over it when it is not English. Safe to call at any time.
static func load_table(lang: String = ENGLISH) -> void:
	_table = _read(DIR + ENGLISH + ".json")
	_lang = lang
	if lang != ENGLISH:
		var over := _read(DIR + lang + ".json")
		for k in over:
			if str(over[k]) != "":
				_table[k] = over[k]
	_parsed.clear()
	_loaded = true


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		_warn("Loc: %s is not a JSON object" % path)
		return {}
	return d


static func _ensure() -> void:
	if not _loaded:
		load_table(_lang)


static func language() -> String:
	return _lang


static func has(key: String) -> bool:
	_ensure()
	return _table.has(key)


## The text of `key` with `vars` put in; the key itself (and one warning) when there is no such row.
static func t(key: String, vars: Dictionary = {}) -> String:
	_ensure()
	if not _table.has(key):
		_warn("Loc: no text for key '%s'" % key)
		return key
	var out := render(str(_table[key]), vars, key)
	if capture:
		_note(key, vars, out)
	return out


## The first of `keys` that has a row (an item's own row before the generic template: ["weapon.revolver.desc",
## "gen.weapon.shot.nearest"]); an empty key is skipped; the last key (and one warning) when none has.
static func t_first(keys: Array, vars: Dictionary = {}) -> String:
	_ensure()
	for k in keys:
		var key := str(k)
		if key != "" and _table.has(key):
			return t(key, vars)
	var last := str(keys[keys.size() - 1]) if not keys.is_empty() else ""
	_warn("Loc: none of %s has a text" % str(keys))
	return last


## A content item's words in the language played: `english` (its JSON field, e.g. a WeaponDef's display_name) unless the
## language's table has `key` (weapon.revolver.name). English always plays the JSON.
static func content(key: String, english: String) -> String:
	if _lang == ENGLISH:
		return english
	_ensure()
	return str(_table[key]) if _table.has(key) else english


## `template` with `vars` put in (the tab's preview and the tests use it too).
static func render(template: String, vars: Dictionary, key: String = "") -> String:
	var segs: Array
	if _parsed.has(template):
		segs = _parsed[template]
	else:
		segs = _parse(template, key)
		_parsed[template] = segs
	return _emit(segs, vars, key)


static func _emit(segs: Array, vars: Dictionary, key: String) -> String:
	var out := ""
	for s in segs:
		if s is String:
			out += s
			continue
		var d: Dictionary = s
		var name: String = d["v"]
		if not vars.has(name):
			_warn("Loc: '%s' has no value for {%s}" % [key, name])
			out += str(d["raw"])
			continue
		var v = vars[name]
		if d.has("one"):
			out += _emit(d["one"] if _is_one(v) else d["many"], vars, key)
		else:
			out += str(v)
	return out


## Exactly 1: the number 1, or the text "1" ("1.0" and "01" choose the second part).
static func _is_one(v) -> bool:
	if v is int:
		return v == 1
	if v is float:
		return v == 1.0
	return str(v).strip_edges() == "1"


## The segments of a template: plain strings and {v, raw} / {v, raw, one, many} placeholders.
static func _parse(src: String, key: String) -> Array:
	var segs: Array = []
	var buf := ""
	var i := 0
	var n := src.length()
	while i < n:
		var c := src[i]
		if c == "{":
			if i + 1 < n and src[i + 1] == "{":
				buf += "{"
				i += 2
				continue
			var close := _closing(src, i)
			if close < 0:
				_warn("Loc: '%s' has a { with no }" % key)
				buf += src.substr(i)
				break
			if buf != "":
				segs.append(buf)
				buf = ""
			segs.append(_placeholder(src.substr(i + 1, close - i - 1), src.substr(i, close - i + 1), key))
			i = close + 1
			continue
		if c == "}":
			if i + 1 < n and src[i + 1] == "}":
				buf += "}"
				i += 2
				continue
			_warn("Loc: '%s' has a } with no {" % key)
		buf += c
		i += 1
	if buf != "":
		segs.append(buf)
	return segs


## The index of the } that closes the { at `open` (placeholders may nest inside a selector's parts), -1 when none.
static func _closing(src: String, open: int) -> int:
	var depth := 0
	var i := open
	while i < src.length():
		var c := src[i]
		if c == "{":
			depth += 1
		elif c == "}":
			depth -= 1
			if depth == 0:
				return i
		i += 1
	return -1


static func _placeholder(inner: String, raw: String, key: String) -> Dictionary:
	var q := inner.find("?")
	if q < 0:
		return {"v": inner.strip_edges(), "raw": raw}
	var rest := inner.substr(q + 1)
	# the ':' between the two parts, outside any {variable} inside them
	var depth := 0
	var split := -1
	for j in range(rest.length()):
		var c := rest[j]
		if c == "{":
			depth += 1
		elif c == "}":
			depth -= 1
		elif c == ":" and depth == 0:
			split = j
			break
	if split < 0:
		_warn("Loc: '%s' has {%s} without its ':' between the two parts" % [key, inner])
		return {"v": inner.substr(0, q).strip_edges(), "raw": raw, "one": _parse(rest, key), "many": _parse(rest, key)}
	return {"v": inner.substr(0, q).strip_edges(), "raw": raw, "one": _parse(rest.substr(0, split), key),
		"many": _parse(rest.substr(split + 1), key)}


## The variable names a template uses, in order, once each (selectors and the variables inside their parts).
static func variables(template: String) -> Array:
	var out: Array = []
	_collect(_parse(template, ""), out)
	return out


static func _collect(segs: Array, out: Array) -> void:
	for s in segs:
		if s is Dictionary:
			if not out.has(s["v"]):
				out.append(s["v"])
			if s.has("one"):
				_collect(s["one"], out)
				_collect(s["many"], out)


static func _warn(msg: String) -> void:
	if _warned.has(msg):
		return
	_warned[msg] = true
	_warnings.append(msg)
	push_warning(msg)


## Every warning so far (each once), and a way to start afresh (tests).
static func warnings() -> Array:
	return _warnings.duplicate()


static func clear_warnings() -> void:
	_warned.clear()
	_warnings.clear()


# ---------------------------------------------------------------- capture mode (tools)

static func _note(key: String, vars: Dictionary, out: String) -> void:
	var vs := {}
	for k in vars:
		vs[str(k)] = str(vars[k])
	_samples[key] = {"vars": vs, "text": out}


static func samples_path() -> String:
	return ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join(SAMPLES_REL)


static func samples() -> Dictionary:
	return _samples.duplicate(true)


## Writes what capture mode saw, merged over what the file held (a key seen now replaces its old sample), keys sorted.
static func write_samples(path: String) -> bool:
	var have := {}
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			have = d
	for k in _samples:
		have[k] = _samples[k]
	var keys := have.keys()
	keys.sort()
	var sorted := {}
	for k in keys:
		sorted[k] = have[k]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(sorted, "  ", false) + "\n")
	return true

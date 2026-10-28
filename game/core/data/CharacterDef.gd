## A playable character: a trait (Effects on the player) plus a favourite weapon with a bonus.
class_name CharacterDef
extends ContentDef

## Effects applied to the player StatSheet at run start (pass 61: empty on the five heroes in play, whose trait is their
## level_trait; the hidden ones keep theirs).
@export var trait_effects: Array = []
## The hero's signature stat (pass 61, Garry: "Heroes have 1-2 unique stats, and they scale as they level up"): Effects
## whose value is what one level gives (JSON "trait_per_level", the "trait" schema). Run._build_player_sheet folds them as
## ONE effect per entry worth value x the hero's level (level_effects), so 40 levels of +1% are +40%, never 1.01^40.
@export var level_trait: Array = []
## Where the hero stands in the title's carousel and every hero list (pass 61: the Drifter 1, Astro 2, Calavera 3,
## Ironwood 4, Solenne 5); Registry.sorted_characters sorts by it, then by id.
@export var order: int = 100
## the trait as the player reads it: a name and one line (traits with a mechanic behind them cannot be generated from effects)
@export var trait_name: String = ""
@export var trait_text: String = ""
## "he", "she" or "they": the words the first-play hints use for the hero ("she shoots by herself")
@export var pronoun: String = "they"
## fraction of max HP healed on every level-up (Astro's suit); 0 for none
@export var level_heal: float = 0.0
## The favourite: FAVOURITE on the title plaque, the hero path sits on it, a bonus when it is picked or when he starts with it.
@export var favourite_weapon: String = ""
## Bonus when the favourite is picked: {"type": "level", "value": 2} or {"type": "effects", "effects": [Effect...]}
@export var favourite_bonus: Dictionary = {}
## The weapon in his hand when he lands (pass 45): his own gun (WeaponDef.hero) by default; empty = the favourite, then
## the Peashooter.
@export var start_weapon: String = ""
## A favourite passive or line (pass 46: Ironwood's Cake; pass 47: his Brawn, the attack-damage line, at level 2), empty
## for none, and what finding it gives, the same shape as favourite_bonus: {"type": "max"} (full at once; on a line that
## would be maxed and offering its evolution at the first pick), {"type": "level", "value": 2} or
## {"type": "effects", "effects": [Effect...]}.
@export var favourite_passive: String = ""
@export var favourite_passive_bonus: Dictionary = {}
## Special rules by id: "cannot_stop", "auto_magnet"
@export var specials: Array = []
## Buck's trait: {"ramp_seconds", "speed_bonus", "might_bonus"}; speed and might climb while unhurt and reset on a hit
@export var momentum: Dictionary = {}
## Quest id that unlocks this character; empty = unlocked from the start.
@export var unlock_quest: String = ""
## Pass 66 (the Level Editor's Heroes tab; Garry: "choose if they are hidden or available (or if they can be purchased
## with currency_type - add this for now, but don't hook up any additional functionality)"): "hidden" | "available" |
## "purchase". Pass 69 wired the loop: "hidden" folds into `hidden`; a "purchase" hero is shown on the title, locked until
## his quest `unlock_<id>` is done, then on sale for `price` in `currency_type` ("gold") until bought (Registry.hero_state,
## Save.buy_hero); "available" is free (owned from the start, or once his quest is done when he has one).
@export var availability: String = "available"
@export var price: int = 0
@export var currency_type: String = "gold"
## Kept but not playable (pass 33.4: Buck, Dad and Mira): out of play setup, the collection and the title screen; its
## art, perks and logic stay for later.
## Pass 101 (lane LOOKS): the strip is kept as a path (`sprite_path`, the res:// path JsonContent resolved; "" = no
## strip) and `sprite` loads it the first time something asks (LookArt: boot loads no strip; a run pins its own set,
## RunLooks). Setting a texture holds that one; setting null clears the path too (no strip). An old .tres that still
## names the texture sets it here and plays as before.
var sprite: Texture2D:
	get:
		return _sprite if _sprite != null else LookArt.tex(sprite_path)
	set(value):
		_sprite = value
		sprite_path = value.resource_path if value != null else ""
var _sprite: Texture2D = null
@export var sprite_path: String = ""
@export var sprite_file: String = ""
@export var frame_px: int = 256
@export var anims: Dictionary = {"idle": 2, "run": 4, "turn": 1, "hit": 1, "die": 1, "cheer": 1}
## Frames per row when the strip is a grid (0 = one row). Written by tools/gen_art.py.
@export var strip_cols: int = 0
## Frames per second per animation prefix, e.g. {"run": 28}; unlisted ones use the sprite player's defaults.
@export var fps: Dictionary = {}
## Art variants (pass 55, the creatures' scheme of pass 34): code -> {sprite, sprite_file, anims, fps, strip_cols, frame_px,
## icon, title, note}, every strip the hero can be drawn with ("SOL-A".."SOL-D", Solenne's walks). `variant` is the look the
## game plays unless the player kept another (Save.hero_look, the arena's HERO tab); its art is the def's own. Only the art
## differs between them: the id, the trait, the perks and the weapons are the hero's whatever look he wears. `title` (pass
## 68) is the look's own title cut-out, a file name under TITLE_DIR ("" = the hero's hero_<id>.png; title_path()).
@export var variants: Dictionary = {}
@export var variant: String = ""
## The look a copy made by variant_def() wears ("" on the def itself, which wears `variant`).
var variant_code := ""
## Where the title cut-outs lie (pass 68): the hero's own hero_<id>.png and the files his looks name (`title`).
const TITLE_DIR := "res://art/ui/wanted/"


func kind() -> String:
	return "character"


## The signature stat at `level` (pass 61): one Effect per level_trait entry, its value times the level (level 1 already
## carries one step, so the trait shows from the first second). Fresh Effects: the def's own are never changed.
func level_effects(level: int) -> Array:
	var out: Array = []
	var n := maxi(level, 0)
	for e in level_trait:
		if e is Effect:
			var x: Effect = e
			out.append(Effect.make(x.stat, x.op, x.value * float(n), x.target))
	return out


## A look entry's strip as this def's own (pass 101): a res:// path (what JsonContent writes since pass 101, loaded
## on the first ask), a texture (an old .tres, a test's or a tool's stand-in entry), or nothing (keeps its own).
func take_strip(s) -> void:
	if s is Texture2D:
		_sprite = s
		sprite_path = (s as Texture2D).resource_path
	elif s is String and str(s) != "":
		_sprite = null
		sprite_path = str(s)


## The res:// path of the strip this def draws ("" when it has none), without loading it.
func strip_path() -> String:
	return _sprite.resource_path if _sprite != null else sprite_path


## The res:// path of the strip look `code` draws (pass 101; the def's own for "", its own code or an unknown one, as
## variant_def falls back), without loading it or making a copy.
func look_strip_path(code: String) -> String:
	if code == "" or code == look_code() or not variants.has(code):
		return strip_path()
	var s = (variants[code] as Dictionary).get("sprite") if variants[code] is Dictionary else null
	if s is Texture2D:
		return (s as Texture2D).resource_path
	return str(s) if s is String and str(s) != "" else strip_path()


## Takes one variant's art (a `variants` entry) as its own.
func apply_art(a: Dictionary) -> void:
	take_strip(a.get("sprite"))
	sprite_file = str(a.get("sprite_file", sprite_file))
	anims = a.get("anims", anims)
	fps = a.get("fps", fps)
	strip_cols = int(a.get("strip_cols", strip_cols))
	frame_px = int(a.get("frame_px", frame_px))
	# pass 101 (lane LOOKS): the entry's icon is its path (LookArt.icon loads it), or a texture
	var ic := LookArt.icon(a.get("icon"))
	if ic != null:
		icon = ic


## This hero drawn with another look: a copy wearing that variant's strip, everything else his. Itself for the look it
## wears already, for "" and for a code it does not have (a look kept for a strip that has since gone), so a missing
## look falls back to the JSON's.
func variant_def(code: String) -> CharacterDef:
	if code == "" or code == look_code() or not variants.has(code):
		return self
	var v: CharacterDef = duplicate()
	v.variant_code = code
	v.source_dir = source_dir
	v.apply_art(variants[code])
	return v


## The look this def wears: the copy's code, else the JSON's `variant` ("" for a hero with one art).
func look_code() -> String:
	return variant_code if variant_code != "" else variant


## The title cut-out the look it wears names (pass 68: `variants[CODE].title`, a file name under TITLE_DIR such as
## "hero_may_b.png", the Level Editor's title pick for that look), "" when it names none.
func look_title() -> String:
	var e = variants.get(look_code())
	return str((e as Dictionary).get("title", "")) if e is Dictionary else ""


## The full-body cut-out shown for the look it wears (pass 68): the look's own (look_title) when that file is there, else
## the hero's own TITLE_DIR/hero_<id>.png (not painted yet = the title's striped slot). Asked of the look the player plays
## (Registry.played_look: the kept look, else the JSON's `variant`, else the base), it is the one the title draws.
func title_path() -> String:
	var f := look_title()
	if f != "":
		var p := f if f.begins_with("res://") else TITLE_DIR + f
		if ResourceLoader.exists(p):
			return p
	return TITLE_DIR + "hero_" + id + ".png"


## The look codes in order (empty when he has one art). A shelved look (`variants[CODE].shelved`, pass 66: the Level
## Editor's shelve, a look kept but out of the way) is left out unless asked for, so the arena chips and the default
## lists skip it; variant_def(code) still wears it when named (a kept look, a map row).
func variant_codes(include_shelved := false) -> Array:
	var out: Array = []
	for code in variants.keys():
		if include_shelved or not variant_shelved(str(code)):
			out.append(code)
	out.sort()
	return out if out.size() > 1 else []


## Whether a look is shelved (pass 66); false for a code he does not have.
func variant_shelved(code: String) -> bool:
	var e = variants.get(code)
	return e is Dictionary and bool((e as Dictionary).get("shelved", false))


## A look's note from the JSON ("" when it has none).
func variant_note(code: String) -> String:
	var e = variants.get(code)
	return str((e as Dictionary).get("note", "")) if e is Dictionary else ""


# ---------------------------------------------------------------- pass 111 (lane SKINS): looks sold as skins

## The name the look every player owns reads as (its own `skin.name` when the JSON gives one).
const HOME_SKIN_NAME := "Classic"


## The look every player owns (pass 111): the one the game plays (`variant`), else the base; "" for a hero with one art.
func home_look() -> String:
	if variant != "" and variants.has(variant):
		return variant
	return ""


## Look `code`'s skin entry (`variants[CODE].skin` in the JSON: {purchasable, name, price, currency_type, unlock_quest});
## {} when it has none.
func skin_of(code: String) -> Dictionary:
	var e = variants.get(code)
	var s = (e as Dictionary).get("skin") if e is Dictionary else null
	return s if s is Dictionary else {}


## Whether look `code` is offered to players as a skin (pass 111): marked purchasable, painted (a strip of its own, or
## the base's), not shelved, and not the look every player owns already.
func sells_skin(code: String) -> bool:
	if not variants.has(code) or code == home_look() or variant_shelved(code):
		return false
	return bool(skin_of(code).get("purchasable", false))


## The name players read for look `code`: its skin's `name`, else HOME_SKIN_NAME for the owned look, else "Look <CODE>".
func skin_name(code: String) -> String:
	var n := str(skin_of(code).get("name", "")).strip_edges()
	if n != "":
		return n
	return HOME_SKIN_NAME if code == home_look() or code == "" else "Look %s" % code


## Its price (0 = free once its goal is done).
func skin_price(code: String) -> int:
	return maxi(int(skin_of(code).get("price", 0)), 0)


## The currency its price is in, as the JSON names it ("gold" when it names none; Currency.of reads an unknown one as gold).
func skin_currency(code: String) -> String:
	var c := str(skin_of(code).get("currency_type", "gold"))
	return c if c != "" else "gold"


## The quest id its JSON names (`skin.unlock_quest`, "" none); Registry.skin_quest finds the quest by its `unlocks` first.
func skin_quest_id(code: String) -> String:
	return str(skin_of(code).get("unlock_quest", ""))


## The full-body still the hero sheet shows for look `code` (pass 111): `skin.still` in the hero's folder, else
## <id>_still_<code, lower case, '-' as '_'>.png (tools/skin_stills.py cuts it from the strip's front idle frame); ""
## when there is none on disk (the sheet shows the look's badge).
func look_still_path(code: String) -> String:
	if code == "":
		code = home_look()
	if code == "":
		return ""
	var f := str(skin_of(code).get("still", ""))
	if f == "":
		f = "%s_still_%s.png" % [id, code.to_lower().replace("-", "_")]
	var p := f if f.begins_with("res://") else source_dir.path_join(f) if source_dir != "" else ""
	return p if p != "" and ResourceLoader.exists(p) else ""

## Pass 116 (lane RESULTS; Garry: "there should be some kind of an indicator that the breath is ready to attack. It can be
## subtle, maybe whenever the little spikey circle implodes in into the Player hero"): the Dragon's Breath's ready sign.
## When the breath's cooldown runs out (FireBreath._tick), a small spiky ring of flame round his face collapses into it in
## TIME seconds and leaves a white spark (core/shaders/breath_ready.gdshader). One quad, made once per breath weapon,
## hidden between signs; see-through, so the stage filters leave its colours alone; an ink outline keeps it readable on
## the sand, Nightfall's blue and Blood Moon's red. Only a look: it never changes the run (no dice, no rule clock).
class_name BreathReady
extends MeshInstance3D

const SHADER := preload("res://core/shaders/breath_ready.gdshader")
## The sign's life (seconds) and its quad's side (metres) at its start.
const TIME := 0.45
const SIDE := 1.1

var _t := -1.0
var _mat: ShaderMaterial
var _follow: Callable


static func make(parent: Node) -> BreathReady:
	var b := BreathReady.new()
	b.name = "BreathReady"
	var q := QuadMesh.new()
	q.size = Vector2(SIDE, SIDE)
	b.mesh = q
	b._mat = ShaderMaterial.new()
	b._mat.shader = SHADER
	b._mat.render_priority = 2
	b.material_override = b._mat
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.visible = false
	b.top_level = true
	parent.add_child(b)
	return b


## The sign plays once from now, kept at `where` (a Callable giving the face's point each frame).
func play(where: Callable, blue := false) -> void:
	_follow = where
	_t = 0.0
	if blue:
		_mat.set_shader_parameter("hot", Color(0.75, 0.92, 1.0))
		_mat.set_shader_parameter("rim", Color(0.15, 0.45, 1.0))
	else:
		_mat.set_shader_parameter("hot", Color(1.0, 0.82, 0.3))
		_mat.set_shader_parameter("rim", Color(0.85, 0.25, 0.05))
	_mat.set_shader_parameter("phase", 0.0)
	visible = true
	_place()


## Whether a sign is showing (tests, captures).
func playing() -> bool:
	return _t >= 0.0


func _place() -> void:
	if _follow.is_valid():
		global_position = _follow.call()


func _process(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	if _t >= TIME:
		_t = -1.0
		visible = false
		return
	_mat.set_shader_parameter("phase", _t / TIME)
	_place()

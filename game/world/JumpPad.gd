## Auto-jump trigger. When the player runs through it roughly along `direction`, they get launched.
## Placed at mesa gap edges (both directions) and ramp tops.
class_name JumpPad
extends Area3D

@export var direction := Vector3(0, 0, -1)
@export var up_speed := 9.0
@export var forward_speed := 7.0
@export var min_alignment := 0.3
@export var both_ways := true

var _cooldown := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body)
	monitoring = true


func _process(delta: float) -> void:
	_cooldown = max(_cooldown - delta, 0.0)


func _on_body(body: Node3D) -> void:
	if _cooldown > 0.0:
		return
	if not body.has_method("launch"):
		return
	var f: Vector3 = body.forward() if body.has_method("forward") else direction
	var d := Vector3(direction.x, 0, direction.z).normalized()
	var align := f.dot(d)
	if align >= min_alignment:
		body.launch(d * forward_speed + Vector3(0, up_speed, 0))
		_cooldown = 0.6
	elif both_ways and align <= -min_alignment:
		body.launch(-d * forward_speed + Vector3(0, up_speed, 0))
		_cooldown = 0.6

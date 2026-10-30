class_name Hurtbox
extends Area2D
## The area of a fighter that can be hit. It shrinks while crouching.

const STAND_SIZE := Vector2(52.0, 170.0)
const CROUCH_SIZE := Vector2(56.0, 110.0)

var fighter: Fighter
var _crouching := false
var _rect := RectangleShape2D.new()

@onready var _shape_node: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	fighter = get_parent() as Fighter
	_shape_node.shape = _rect
	_apply()


func set_crouching(value: bool) -> void:
	if value == _crouching:
		return
	_crouching = value
	_apply()


func _apply() -> void:
	var size := CROUCH_SIZE if _crouching else STAND_SIZE
	_rect.size = size
	_shape_node.position = Vector2(0.0, -size.y * 0.5)

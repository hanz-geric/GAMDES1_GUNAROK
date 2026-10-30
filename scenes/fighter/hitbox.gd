class_name Hitbox
extends Area2D
## Attack hitbox. Damage applies only if it overlaps the defender's hurtbox
## during the active phase (GDD Section II, Procedures step 4).

signal hit_landed(attacker: Fighter, defender: Fighter, damage: float, blocked: bool)

## Vertical centre and height of the hitbox for each attack height.
const HEIGHT_Y := {&"high": -138.0, &"mid": -150.0, &"low": -42.0}
const HEIGHT_SIZE := {&"high": 46.0, &"mid": 260.0, &"low": 50.0}

var fighter: Fighter
var active := false
var _has_hit := false
var _height: StringName = &"high"
var _damage := 0.0
var _rect := RectangleShape2D.new()

@onready var _shape_node: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	fighter = get_parent() as Fighter
	_rect.size = Vector2(8.0, 8.0)
	_shape_node.shape = _rect


## Called at the start of an attack so the shape is in place before the
## active phase begins.
func prepare(height: StringName, facing: int, length: float, damage: float) -> void:
	_height = height
	_damage = damage
	var size_y: float = HEIGHT_SIZE[height]
	var centre_y: float = HEIGHT_Y[height]
	_rect.size = Vector2(length, size_y)
	_shape_node.position = Vector2(facing * (Balance.BODY_HALF_WIDTH + length * 0.5), centre_y)
	active = false
	_has_hit = false


func activate() -> void:
	active = true
	_has_hit = false


func deactivate() -> void:
	active = false


func _physics_process(_delta: float) -> void:
	if not active or _has_hit:
		return
	for area in get_overlapping_areas():
		var hurtbox := area as Hurtbox
		if hurtbox == null or hurtbox.fighter == fighter:
			continue
		var defender := hurtbox.fighter
		if not defender.can_be_hit():
			continue
		# Height rules (GDD Section II): punches miss crouching fighters,
		# kicks miss jumping fighters, the special hits both.
		if _height == &"high" and defender.is_crouching():
			continue
		if _height == &"low" and defender.is_airborne():
			continue
		var blocked := defender.is_blocking()
		var amount := _damage * (Balance.CHIP_RATIO if blocked else 1.0)
		_has_hit = true
		hit_landed.emit(fighter, defender, amount, blocked)
		return

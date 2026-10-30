class_name WarriorData
extends Resource
## One playable warrior or the god boss. Each warrior's three ratings add up
## to the 9-point budget in GDD Section 6.3 (Table C).

@export var id: StringName = &""
@export var display_name: String = ""
@export var homeland: String = ""
@export var era: String = ""
@export var special_name: String = ""

@export_group("Stats (1 to 5, budget 9)")
@export_range(1, 5) var damage_rating: int = 3
@export_range(1, 5) var reach_rating: int = 3
@export_range(1, 5) var speed_rating: int = 3
@export var max_health: int = 100
@export var is_boss: bool = false
## Extra hitbox length for the special only (for example a rifle shot).
@export var special_reach_bonus: float = 0.0

@export_group("Look")
@export var weapon: StringName = &"fists"
@export var headgear: StringName = &"none"
@export var skin_color: Color = Color(0.85, 0.65, 0.5)
@export var hair_color: Color = Color(0.1, 0.08, 0.06)
@export var primary_color: Color = Color(0.6, 0.2, 0.2)
@export var secondary_color: Color = Color(0.25, 0.2, 0.2)
## Used for Player 2 when both players pick the same warrior (GDD 8.2).
@export var alt_primary_color: Color = Color(0.2, 0.3, 0.6)
@export var alt_secondary_color: Color = Color(0.2, 0.2, 0.25)
@export var accent_color: Color = Color(1.0, 0.8, 0.3)
## Alpha 0 means no cape.
@export var cape_color: Color = Color(0, 0, 0, 0)
@export var bare_arms: bool = true
@export var bare_torso: bool = false
@export var bare_shins: bool = false
## Optional. When set, Fighter uses AnimatedSprite2D instead of the
## placeholder rig. Expected animations: idle, walk, jump, crouch, block,
## crouch_block, punch, kick, special, hitstun, knockdown, getup, ko, victory.
@export var sprite_frames: SpriteFrames


func stat_total() -> int:
	return damage_rating + reach_rating + speed_rating


func damage_multiplier() -> float:
	var value: float = Balance.DAMAGE_BY_RATING[clampi(damage_rating, 1, 5) - 1]
	return value


func reach_length() -> float:
	return Balance.REACH_BASE + Balance.REACH_PER_RATING * reach_rating


func walk_speed() -> float:
	return Balance.WALK_SPEED_BASE + Balance.WALK_SPEED_PER_RATING * speed_rating


func timing_scale() -> float:
	var value: float = Balance.TIMING_SCALE_BY_SPEED[clampi(speed_rating, 1, 5) - 1]
	return value

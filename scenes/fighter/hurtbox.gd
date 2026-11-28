class_name Hurtbox
extends RefCounted
## Pure box-math hurtbox for a fighter (no Area2D physics dependency,
## Design Plan v3 Section 13.3). Shrinks vertically while crouching.

var crouching := false


func set_crouching(value: bool) -> void:
	crouching = value


func get_rect(origin: Vector2) -> Rect2:
	var size := Balance.HURTBOX_CROUCH_SIZE if crouching else Balance.HURTBOX_STAND_SIZE
	return Rect2(origin.x - size.x * 0.5, origin.y - size.y, size.x, size.y)


func export_state() -> Dictionary:
	return {"crouching": crouching}


func import_state(data: Dictionary) -> void:
	crouching = data["crouching"]

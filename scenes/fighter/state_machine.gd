class_name StateMachine
extends Node
## Holds a fighter's current state and how many 60 Hz frames it has been in it
## (Design Plan v3 Sections 13.3 and 14.2).

enum State {
	IDLE,
	WALK,
	DASH,
	CROUCH,
	JUMP,
	BLOCK,
	CROUCH_BLOCK,
	PARRY,
	PARRY_FAIL,
	PARRIED,
	ATTACK,
	SEIZE_THROW,
	GRABBED,
	HITSTUN,
	KNOCKDOWN,
	GETUP,
	KO,
	VICTORY,
}

signal state_changed(previous: State, current: State)

var state: State = State.IDLE
var frames_in_state := 0


func change(next: State) -> void:
	if next == state:
		return
	force(next)


## Enters a state even if it is the current one (restarts its frame counter).
func force(next: State) -> void:
	var previous := state
	state = next
	frames_in_state = 0
	state_changed.emit(previous, next)


func step_tick() -> void:
	frames_in_state += 1


func export_state() -> Dictionary:
	return {
		"state": int(state),
		"frames_in_state": frames_in_state,
	}


func import_state(data: Dictionary) -> void:
	state = int(data["state"]) as State
	frames_in_state = data["frames_in_state"]

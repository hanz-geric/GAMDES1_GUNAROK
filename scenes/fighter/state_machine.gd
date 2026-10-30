class_name StateMachine
extends Node
## Holds a fighter's current state and how long it has been in it.

enum State { IDLE, WALK, CROUCH, JUMP, BLOCK, CROUCH_BLOCK, ATTACK, HITSTUN, KNOCKDOWN, GETUP, KO, VICTORY }

signal state_changed(previous: State, current: State)

var state: State = State.IDLE
var time_in_state := 0.0


func change(next: State) -> void:
	if next == state:
		return
	force(next)


## Enters a state even if it is the current one (restarts its timer).
func force(next: State) -> void:
	var previous := state
	state = next
	time_in_state = 0.0
	state_changed.emit(previous, next)


func tick(delta: float) -> void:
	time_in_state += delta

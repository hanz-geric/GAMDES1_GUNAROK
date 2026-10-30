class_name CpuTier
extends Resource
## CPU settings for one Arcade match (GDD Table B in Section 6.2 and the
## randomness rules in Section 6.4).

const BLOCK_CHANCE_CAP := 0.55

@export var tier_name: String = "Tier 1"
## Seconds before the CPU can react to a threat.
@export var reaction_delay: float = 0.6
@export_range(0.0, 1.0) var block_chance: float = 0.15
## Average seconds between CPU attacks.
@export var attack_gap: float = 2.0
@export var attack_gap_jitter: float = 0.3
@export var min_attack_gap: float = 0.5
@export var health: int = 100
@export var damage_multiplier: float = 0.8
## Above 1.0 the CPU winds up its attacks more slowly (easier to read).
@export var windup_scale: float = 1.0
## Multiplies attack_gap from round 2 on (M1 attacks more often in round 2).
@export var later_round_gap_scale: float = 1.0
## Seconds the CPU waits before attacking in round 1 (M1 only).
@export var idle_start_time: float = 0.0
## M2: backs away when ahead on health, which teaches the time-out rule.
@export var retreats_when_ahead: bool = false
## M3 and M5: keeps pressing forward, which pushes the player into a corner.
@export var presses_to_corner: bool = false
## Chance to pick the special when it has 50 or more meter.
@export_range(0.0, 1.0) var special_weight: float = 0.3


func capped_block_chance() -> float:
	return minf(block_chance, BLOCK_CHANCE_CAP)

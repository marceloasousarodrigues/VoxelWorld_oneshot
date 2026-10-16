class_name Survival
extends RefCounted

## Pure, deterministic survival rules for the M17 Godot voxel game.
##
## Every function is static and side-effect free, so the rules can be tuned and
## tested without a scene tree.  The game layer owns the mutable state (health,
## breath, time since the last hit) and calls these to decide how it should
## change.  Nothing here touches a node, the world or the HUD.

# --- fall damage -----------------------------------------------------------
## Falls of this many blocks or fewer are free.  A fall of `d` blocks costs
## `(d - SAFE_FALL_DISTANCE) * FALL_DAMAGE_PER_BLOCK` health, so the damage is
## Minecraft-like: "fall distance minus three".
const SAFE_FALL_DISTANCE := 3.0
const FALL_DAMAGE_PER_BLOCK := 1.0

# --- breath / drowning -----------------------------------------------------
## Seconds of breath when full.  A full breath lasts MAX_BREATH / drain seconds
## underwater.
const MAX_BREATH := 15.0
## Breath lost per second while the head is under water.
const BREATH_DRAIN_PER_SECOND := 1.0
## Breath regained per second once the head is out of water.
const BREATH_REFILL_PER_SECOND := 4.0
## Health lost per second spent submerged with no breath left.
const DROWN_DAMAGE_PER_SECOND := 1.0

# --- regeneration ----------------------------------------------------------
## A body that has taken no damage for this long starts healing naturally.
const REGEN_DELAY_SECONDS := 8.0
## Health restored per second while regenerating.
const REGEN_PER_SECOND := 0.5


## Health lost by a fall of `fall_distance_blocks`; never negative.
static func fall_damage(fall_distance_blocks: float) -> float:
	if fall_distance_blocks <= SAFE_FALL_DISTANCE:
		return 0.0
	return (fall_distance_blocks - SAFE_FALL_DISTANCE) * FALL_DAMAGE_PER_BLOCK


## One breath step.  While `submerged` breath drains and, once it is empty, the
## time spent with no breath deals drowning damage; otherwise breath refills up
## to `max_breath`.  Returns `{"breath": float, "damage": float}`.
static func breath_step(breath: float, max_breath: float, submerged: bool, delta: float) -> Dictionary:
	var maximum := maxf(0.0, max_breath)
	var value := clampf(breath, 0.0, maximum)
	var step := maxf(0.0, delta)
	if not submerged:
		return {"breath": minf(maximum, value + BREATH_REFILL_PER_SECOND * step), "damage": 0.0}
	var remaining := value - BREATH_DRAIN_PER_SECOND * step
	if remaining >= 0.0:
		return {"breath": remaining, "damage": 0.0}
	# The step crossed zero, so only the part of it spent with no breath left
	# deals damage instead of charging a whole tick for a partial one.
	var drown_seconds := -remaining / BREATH_DRAIN_PER_SECOND
	return {"breath": 0.0, "damage": drown_seconds * DROWN_DAMAGE_PER_SECOND}


## One regeneration step.  `seconds_since_damage` is how long the body has gone
## without taking damage.  Returns `{"health": float, "healed": float}`.  A full
## or dead body never regenerates, and nothing happens before the delay elapses.
static func regen_step(health: float, max_health: float, seconds_since_damage: float, delta: float) -> Dictionary:
	var maximum := maxf(0.0, max_health)
	var value := clampf(health, 0.0, maximum)
	if value <= 0.0 or value >= maximum or seconds_since_damage < REGEN_DELAY_SECONDS:
		return {"health": value, "healed": 0.0}
	var healed := minf(maximum - value, REGEN_PER_SECOND * maxf(0.0, delta))
	return {"health": value + healed, "healed": healed}

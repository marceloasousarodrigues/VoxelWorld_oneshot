class_name Health
extends RefCounted

## Deterministic, node-free health model for the M17 Godot voxel game.
##
## It owns a current and a maximum value, clamps every change into range, and
## reports what it did through signals so the game layer can react (HUD refresh,
## hurt feedback, death).  It knows nothing about the scene tree, the player or
## the world, so it can be unit-tested and serialised on its own.
##
## Death is a one-way transition until `revive()`: once health reaches zero the
## body takes no further damage, cannot heal and never emits `died` again.

signal changed()
signal damaged(amount: float, source: String)
signal died()

const DEFAULT_MAX_HEALTH := 20.0

var max_health := DEFAULT_MAX_HEALTH
var health := DEFAULT_MAX_HEALTH


## `current` below zero means "start full", which is what a fresh body wants.
func _init(maximum: float = DEFAULT_MAX_HEALTH, current: float = -1.0) -> void:
	max_health = maximum if maximum > 0.0 else DEFAULT_MAX_HEALTH
	health = max_health if current < 0.0 else clampf(current, 0.0, max_health)


## Applies damage and returns how much was actually applied (never more than the
## health that was left).  A dead body is inert: it applies no damage and emits
## nothing, so `died` cannot fire twice.
func apply_damage(amount: float, source: String = "") -> float:
	if amount <= 0.0 or is_dead():
		return 0.0
	var applied := minf(amount, health)
	health -= applied
	damaged.emit(applied, source)
	changed.emit()
	if health <= 0.0:
		died.emit()
	return applied


## Restores health and returns how much was actually restored.  A dead body
## cannot heal; a full body heals nothing and emits nothing.
func heal(amount: float) -> float:
	if amount <= 0.0 or is_dead():
		return 0.0
	var applied := minf(amount, max_health - health)
	if applied <= 0.0:
		return 0.0
	health += applied
	changed.emit()
	return applied


## Directly sets health, clamped into `[0, max_health]`.
func set_health(value: float) -> void:
	var was_alive := health > 0.0
	var clamped := clampf(value, 0.0, max_health)
	if clamped == health:
		return
	health = clamped
	changed.emit()
	if was_alive and health <= 0.0:
		died.emit()


## Returns a dead body to full health.
func revive() -> void:
	if health == max_health:
		return
	health = max_health
	changed.emit()


func is_dead() -> bool:
	return health <= 0.0


## Health as a fraction of the maximum, in `[0, 1]`.
func ratio() -> float:
	if max_health <= 0.0:
		return 0.0
	return clampf(health / max_health, 0.0, 1.0)


func to_dictionary() -> Dictionary:
	return {"max_health": max_health, "health": health}


## Restores from a save payload.  A non-numeric or non-positive maximum and a
## non-numeric health value are rejected; an out-of-range health is clamped.  A
## rejected payload leaves the model untouched.
func from_dictionary(data: Dictionary) -> bool:
	var maximum: Variant = data.get("max_health")
	if typeof(maximum) != TYPE_FLOAT and typeof(maximum) != TYPE_INT:
		return false
	if float(maximum) <= 0.0:
		return false
	var value: Variant = data.get("health")
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return false
	max_health = float(maximum)
	health = clampf(float(value), 0.0, max_health)
	changed.emit()
	return true

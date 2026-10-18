class_name GameSettings
extends RefCounted

## Player-facing configuration: render distance, mouse sensitivity and vsync.
##
## Pure data with clamping so a corrupt config file or a hostile value can never
## take the game out of its valid range.  The game layer owns persistence
## (`ConfigFile`) and applying the values to the streamer, player and display.

const RENDER_DISTANCE_MIN := 2
const RENDER_DISTANCE_MAX := 8
const RENDER_DISTANCE_DEFAULT := 4
const SENSITIVITY_MIN := 0.0005
const SENSITIVITY_MAX := 0.006
const SENSITIVITY_DEFAULT := 0.0022

var render_distance := RENDER_DISTANCE_DEFAULT
var mouse_sensitivity := SENSITIVITY_DEFAULT
var vsync := true


func set_render_distance(value: float) -> int:
	render_distance = clampi(int(round(value)), RENDER_DISTANCE_MIN, RENDER_DISTANCE_MAX)
	return render_distance


func set_mouse_sensitivity(value: float) -> float:
	mouse_sensitivity = clampf(value, SENSITIVITY_MIN, SENSITIVITY_MAX)
	return mouse_sensitivity


func set_vsync(value: bool) -> bool:
	vsync = value
	return vsync


func to_dictionary() -> Dictionary:
	return {
		"render_distance": render_distance,
		"mouse_sensitivity": mouse_sensitivity,
		"vsync": vsync,
	}


## Applies a persisted payload.  Only well-typed keys are read; out-of-range
## numbers are clamped by the setters.  Returns true when at least one key was
## applied (false means the payload was unusable and nothing changed).
func from_dictionary(data: Dictionary) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var applied := false
	if data.has("render_distance"):
		var distance: Variant = data["render_distance"]
		if typeof(distance) == TYPE_INT or typeof(distance) == TYPE_FLOAT:
			set_render_distance(float(distance))
			applied = true
	if data.has("mouse_sensitivity"):
		var sensitivity: Variant = data["mouse_sensitivity"]
		if typeof(sensitivity) == TYPE_INT or typeof(sensitivity) == TYPE_FLOAT:
			set_mouse_sensitivity(float(sensitivity))
			applied = true
	if data.has("vsync"):
		var vsync_value: Variant = data["vsync"]
		if typeof(vsync_value) == TYPE_BOOL:
			set_vsync(bool(vsync_value))
			applied = true
	return applied

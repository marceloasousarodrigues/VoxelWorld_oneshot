class_name GameSettings
extends RefCounted

## Player-facing configuration: render distance, mouse sensitivity, vsync and
## camera view/distance.
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
const CAMERA_DISTANCE_MIN := 2.0
const CAMERA_DISTANCE_MAX := 8.0
const CAMERA_DISTANCE_DEFAULT := 3.8
const CAMERA_SHOULDER_MIN := 0.0
const CAMERA_SHOULDER_MAX := 1.0
const CAMERA_SHOULDER_DEFAULT := 0.70
const CAMERA_MODE_FIRST := "first_person"
const CAMERA_MODE_THIRD := "third_person"
const CAMERA_MODES := [CAMERA_MODE_FIRST, CAMERA_MODE_THIRD]

var render_distance := RENDER_DISTANCE_DEFAULT
var mouse_sensitivity := SENSITIVITY_DEFAULT
var vsync := true
var camera_mode := CAMERA_MODE_FIRST
var camera_distance := CAMERA_DISTANCE_DEFAULT
var camera_shoulder := CAMERA_SHOULDER_DEFAULT


func set_render_distance(value: float) -> int:
	render_distance = clampi(int(round(value)), RENDER_DISTANCE_MIN, RENDER_DISTANCE_MAX)
	return render_distance


func set_mouse_sensitivity(value: float) -> float:
	mouse_sensitivity = clampf(value, SENSITIVITY_MIN, SENSITIVITY_MAX)
	return mouse_sensitivity


func set_vsync(value: bool) -> bool:
	vsync = value
	return vsync


## Unknown mode names fall back to the default instead of leaving an invalid
## state that the camera layer would have to guess about.
func set_camera_mode(value: String) -> String:
	camera_mode = value if CAMERA_MODES.has(value) else CAMERA_MODE_FIRST
	return camera_mode


func set_camera_distance(value: float) -> float:
	camera_distance = clampf(value, CAMERA_DISTANCE_MIN, CAMERA_DISTANCE_MAX)
	return camera_distance


## Horizontal over-the-shoulder offset.  Zero centres the camera behind the
## player; larger positive values put the camera to the player's right and the
## character left of the crosshair.
func set_camera_shoulder(value: float) -> float:
	camera_shoulder = clampf(value, CAMERA_SHOULDER_MIN, CAMERA_SHOULDER_MAX)
	return camera_shoulder


func to_dictionary() -> Dictionary:
	return {
		"render_distance": render_distance,
		"mouse_sensitivity": mouse_sensitivity,
		"vsync": vsync,
		"camera_mode": camera_mode,
		"camera_distance": camera_distance,
		"camera_shoulder": camera_shoulder,
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
	if data.has("camera_mode"):
		var mode_value: Variant = data["camera_mode"]
		if typeof(mode_value) == TYPE_STRING:
			set_camera_mode(str(mode_value))
			applied = true
	if data.has("camera_distance"):
		var distance_value: Variant = data["camera_distance"]
		if typeof(distance_value) == TYPE_INT or typeof(distance_value) == TYPE_FLOAT:
			set_camera_distance(float(distance_value))
			applied = true
	if data.has("camera_shoulder"):
		var shoulder_value: Variant = data["camera_shoulder"]
		if typeof(shoulder_value) == TYPE_INT or typeof(shoulder_value) == TYPE_FLOAT:
			set_camera_shoulder(float(shoulder_value))
			applied = true
	return applied

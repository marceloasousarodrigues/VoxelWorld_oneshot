class_name DayNight
extends RefCounted

## Deterministic day/night clock and the lighting curves derived from it.
##
## The clock is a single float in `[0, 1)`: 0.0 is sunrise, 0.25 is noon, 0.5 is
## sunset and 0.75 is midnight.  Every visual value the game needs (sun angles,
## light energy, ambient energy, sky and fog colours) is a pure function of that
## value, so a capture taken at `--time=0.75` is reproducible and the whole thing
## is testable without a scene tree.

const DAY_LENGTH_SECONDS := 900.0

## Sun elevation at noon, in degrees.  Below 90 so the sky keeps a visible zenith.
const NOON_ELEVATION := 74.0

# Palette of the sky at noon and at midnight; everything in between is lerped by
# the smooth `daylight()` factor.
const DAY_SKY_TOP := Color("1f5d97")
const DAY_SKY_HORIZON := Color("c2d9e0")
const NIGHT_SKY_TOP := Color("060c1f")
const NIGHT_SKY_HORIZON := Color("1d2b4a")
const DAY_GROUND_BOTTOM := Color("7f97a6")
const DAY_GROUND_HORIZON := Color("c6d7dd")
const NIGHT_GROUND_BOTTOM := Color("0a1020")
const NIGHT_GROUND_HORIZON := Color("18233a")
const DAY_FOG := Color("c6d9dd")
const NIGHT_FOG := Color("111a30")
const DAY_SUN := Color("fff2dd")
const NIGHT_SUN := Color("a9bde8")
const DAY_WATER_TINT := Color(0.17, 0.40, 0.72)
const NIGHT_WATER_TINT := Color(0.060, 0.140, 0.300)

const DAY_SUN_ENERGY := 1.22
const NIGHT_SUN_ENERGY := 0.45
const DAY_AMBIENT_ENERGY := 1.15
const NIGHT_AMBIENT_ENERGY := 1.05
## Warm band added to the sky horizon at dawn and dusk.
const SUNSET_COLOR := Color("ff7a3a")
## Ambient colour used for the non-sky part of the fill light.  Ambient is taken
## from the sky during the day, but a night sky is almost black, so at night the
## fill must come from this colour instead or the world is unreadable.
const DAY_AMBIENT := Color("a9c6de")
const NIGHT_AMBIENT := Color("465a86")

## Half-width, in sine-of-elevation space, of the dawn/dusk transition.  0.24 is
## about 14 degrees of sun elevation, so twilight lasts long enough to see.
const TWILIGHT := 0.24
## The light never drops below this elevation, so at night the world is lit from
## above (moonlight) instead of from underneath.
const NIGHT_LIGHT_ELEVATION := 15.0

## Current time of day in `[0, 1)`.
var time_of_day := 0.28
## Full cycle length in seconds; `0` freezes the clock.
var day_length_seconds := DAY_LENGTH_SECONDS
## How many whole days have passed since the world started.  Bumped when the
## clock wraps past midnight, so gameplay (raids) can key off the day number.
var day_index := 0


func _init(start_time: float = 0.28, cycle_seconds: float = DAY_LENGTH_SECONDS) -> void:
	time_of_day = fposmod(start_time, 1.0)
	day_length_seconds = maxf(0.0, cycle_seconds)


func set_time(value: float) -> void:
	time_of_day = fposmod(value, 1.0)
	# A deliberate jump is not "time passing", so the day counter only follows a
	# wrap, which `set_time` cannot produce (the value is already wrapped).
	if value < 0.0:
		day_index += 1


func advance(delta: float) -> void:
	if day_length_seconds <= 0.0:
		return
	var advanced := time_of_day + delta / day_length_seconds
	if advanced >= 1.0:
		day_index += int(floor(advanced))
	set_time(advanced)


## Height of the sun above the horizon, in degrees; negative at night.
func sun_elevation() -> float:
	return NOON_ELEVATION * sin(TAU * time_of_day)


## `0` at night, `1` in full daylight, smooth across dawn and dusk.
func daylight() -> float:
	return smoothstep(-TWILIGHT, TWILIGHT, sin(TAU * time_of_day))


func is_night() -> bool:
	return sin(TAU * time_of_day) < -TWILIGHT


## Rotation for the `DirectionalLight3D` that represents the sun.  At night the
## direction is clamped above the horizon so the light comes from the sky rather
## than from under the world.
func sun_angles() -> Vector2:
	return Vector2(-maxf(sun_elevation(), NIGHT_LIGHT_ELEVATION), -90.0 - time_of_day * 360.0)


func sun_energy() -> float:
	return lerpf(NIGHT_SUN_ENERGY, DAY_SUN_ENERGY, daylight())


func sun_color() -> Color:
	return NIGHT_SUN.lerp(DAY_SUN, daylight())


func ambient_energy() -> float:
	return lerpf(NIGHT_AMBIENT_ENERGY, DAY_AMBIENT_ENERGY, daylight())


## How much of the ambient fill comes from the sky.  At night the sky is the
## problem, so the colour term takes over.
func ambient_sky_contribution() -> float:
	return lerpf(0.15, 1.0, daylight())


func ambient_color() -> Color:
	return NIGHT_AMBIENT.lerp(DAY_AMBIENT, daylight())


func sky_top_color() -> Color:
	return NIGHT_SKY_TOP.lerp(DAY_SKY_TOP, daylight())


func sky_horizon_color() -> Color:
	return NIGHT_SKY_HORIZON.lerp(DAY_SKY_HORIZON, daylight())


func ground_bottom_color() -> Color:
	return NIGHT_GROUND_BOTTOM.lerp(DAY_GROUND_BOTTOM, daylight())


func ground_horizon_color() -> Color:
	return NIGHT_GROUND_HORIZON.lerp(DAY_GROUND_HORIZON, daylight())


func fog_color() -> Color:
	return NIGHT_FOG.lerp(DAY_FOG, daylight())


## Tint multiplied into the water texture; dimmer and less saturated at night.
func water_tint() -> Color:
	return NIGHT_WATER_TINT.lerp(DAY_WATER_TINT, daylight())


## `1` at sunrise/sunset, `0` at noon and deep night.  Drives the warm horizon
## band in the sky shader without touching the tested `daylight()` curve.
func horizon_warmth() -> float:
	return 1.0 - smoothstep(0.0, TWILIGHT, absf(sin(TAU * time_of_day)))


func sunset_color() -> Color:
	return SUNSET_COLOR


func sunset_amount() -> float:
	return horizon_warmth() * 0.8


## Stars appear only once daylight has fallen well below half.
func star_amount() -> float:
	return clampf(1.0 - daylight() * 2.2, 0.0, 1.0)


func cloud_amount() -> float:
	return lerpf(0.34, 0.55, daylight())


## Wall-clock hour the in-game time maps to, for the HUD (`0.0` = sunrise = 06:00).
func hour_of_day() -> float:
	return fposmod(time_of_day * 24.0 + 6.0, 24.0)


func clock_text() -> String:
	var hour := hour_of_day()
	var minutes := int(round((hour - floor(hour)) * 60.0))
	var whole_hours := int(floor(hour))
	if minutes >= 60:
		minutes = 0
		whole_hours = (whole_hours + 1) % 24
	return "%02d:%02d" % [whole_hours, minutes]


func phase_name() -> String:
	var rising := cos(TAU * time_of_day) > 0.0
	var height := sin(TAU * time_of_day)
	if height < -TWILIGHT:
		return "Night"
	if height > TWILIGHT:
		return "Day"
	return "Dawn" if rising else "Dusk"


func to_dictionary() -> Dictionary:
	return {"time_of_day": time_of_day, "day_length_seconds": day_length_seconds,
		"day_index": day_index}


## Restores from a save payload; unreadable values keep the current clock.
func from_dictionary(data: Dictionary) -> bool:
	var value: Variant = data.get("time_of_day")
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return false
	set_time(float(value))
	var length: Variant = data.get("day_length_seconds")
	if typeof(length) == TYPE_FLOAT or typeof(length) == TYPE_INT:
		day_length_seconds = maxf(0.0, float(length))
	# The day counter decides when raids happen, so it has to survive a save: an
	# older save simply has none and starts its calendar again.
	var days: Variant = data.get("day_index")
	if typeof(days) == TYPE_FLOAT or typeof(days) == TYPE_INT:
		day_index = maxi(0, int(days))
	return true

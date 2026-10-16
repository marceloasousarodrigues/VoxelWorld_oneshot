extends RefCounted

## Day/night clock: wrap semantics, the lighting curves derived from the time of
## day, determinism, the HUD clock text and save round-tripping.


func name() -> String:
	return "day/night clock"


func run(h: TestHarness) -> void:
	h.section("day/night clock")

	# --- time wrapping is total and lossless for values inside the day --------
	var clock := DayNight.new(0.0)
	h.eq(clock.time_of_day, 0.0, "the clock starts where it was told")
	clock.set_time(1.25)
	h.approx(clock.time_of_day, 0.25, 1e-9, "a time past one day wraps back into the day")
	clock.set_time(-0.25)
	h.approx(clock.time_of_day, 0.75, 1e-9, "a negative time wraps forward")
	clock.advance(0.0)
	h.approx(clock.time_of_day, 0.75, 1e-9, "advancing by zero does not move the clock")

	# --- advancing is linear in seconds --------------------------------------
	var short_day := DayNight.new(0.0, 100.0)
	short_day.advance(25.0)
	h.approx(short_day.time_of_day, 0.25, 1e-9, "a quarter of a 100 s day is a quarter of the cycle")
	short_day.advance(100.0)
	h.approx(short_day.time_of_day, 0.25, 1e-9, "a full cycle returns to the same time")
	for step in 7:
		short_day.advance(13.0)
	h.approx(short_day.time_of_day, fposmod(0.25 + 7.0 * 0.13, 1.0), 1e-6, "many small steps equal their sum")

	# --- a frozen clock never moves -----------------------------------------
	var frozen := DayNight.new(0.75, 0.0)
	frozen.advance(1000.0)
	h.approx(frozen.time_of_day, 0.75, 1e-9, "a zero-length day freezes the clock")
	h.check(frozen.is_night(), "0.75 of the cycle is night, frozen or not")

	# --- the sun rises and sets ---------------------------------------------
	var probe := DayNight.new(0.0)
	h.approx(probe.sun_elevation(), 0.0, 1e-6, "the sun is on the horizon at sunrise")
	h.approx(probe.daylight(), 0.5, 1e-6, "sunrise is halfway between night and day")
	probe.set_time(0.25)
	h.approx(probe.sun_elevation(), DayNight.NOON_ELEVATION, 1e-5, "the sun is highest at noon")
	h.approx(probe.daylight(), 1.0, 1e-6, "noon is full daylight")
	h.check(not probe.is_night(), "noon is not night")
	probe.set_time(0.5)
	h.approx(probe.sun_elevation(), 0.0, 1e-6, "the sun sets at 0.5 of the cycle")
	h.approx(probe.daylight(), 0.5, 1e-6, "sunset is halfway between day and night")
	probe.set_time(0.75)
	h.approx(probe.sun_elevation(), -DayNight.NOON_ELEVATION, 1e-5, "the sun is lowest at midnight")
	h.approx(probe.daylight(), 0.0, 1e-6, "midnight is zero daylight")
	h.check(probe.is_night(), "midnight is night")

	# --- daylight is continuous and bounded ---------------------------------
	# A 200-step sweep: the value must stay in range and never step by more than
	# the true maximum slope of the curve (smoothstep over sin crosses the horizon
	# at ~0.15 per 1/200 of a day).  A discontinuity would step by ~1.0.
	var previous := -1.0
	for index in 201:
		var t := float(index) / 200.0
		probe.set_time(t)
		var value := probe.daylight()
		if value < 0.0 or value > 1.0:
			h.check(false, "daylight left [0, 1] at t=%f" % t)
		if previous >= 0.0 and absf(value - previous) > 0.2:
			h.check(false, "daylight jumped by more than 0.2 at t=%f" % t)
		previous = value
	# Continuity across the horizon itself, at a much finer step: the two values
	# straddle sunset, so their difference is the curve's slope (≈0.006 here) and
	# not a discontinuity (which would be ≈1.0).
	var before := DayNight.new(0.5 - 0.0001)
	var after := DayNight.new(0.5 + 0.0001)
	h.approx(before.daylight(), 0.5, 0.01, "daylight is half way at sunset")
	h.approx(after.daylight(), before.daylight(), 0.02, "daylight is continuous across sunset")

	# --- derived lighting tracks the daylight factor -------------------------
	probe.set_time(0.25)
	var noon_energy := probe.sun_energy()
	var noon_ambient := probe.ambient_energy()
	var noon_top := probe.sky_top_color()
	var noon_fog := probe.fog_color()
	probe.set_time(0.75)
	h.greater(noon_energy, probe.sun_energy(), "the sun is brighter at noon than at midnight")
	h.greater(noon_ambient, probe.ambient_energy(), "ambient light is brighter at noon than at midnight")
	h.greater(noon_top.get_luminance(), probe.sky_top_color().get_luminance(), "the sky is brighter at noon than at midnight")
	h.greater(noon_fog.get_luminance(), probe.fog_color().get_luminance(), "day fog is brighter than night fog")
	h.eq(probe.sun_color(), DayNight.NIGHT_SUN, "the midnight light is the night colour")

	# The lighting curves are monotonic across a dawn: no dip in the middle.
	probe.set_time(0.0)
	var dawn_energy := probe.sun_energy()
	probe.set_time(0.06)
	var morning_energy := probe.sun_energy()
	probe.set_time(0.12)
	h.check(dawn_energy <= morning_energy and morning_energy <= probe.sun_energy(),
		"sun energy rises monotonically out of sunrise")

	# --- the HUD clock maps sunrise to 06:00 --------------------------------
	probe.set_time(0.0)
	h.eq(probe.clock_text(), "06:00", "sunrise reads 06:00")
	probe.set_time(0.25)
	h.eq(probe.clock_text(), "12:00", "noon reads 12:00")
	probe.set_time(0.5)
	h.eq(probe.clock_text(), "18:00", "sunset reads 18:00")
	probe.set_time(0.75)
	h.eq(probe.clock_text(), "00:00", "midnight reads 00:00")
	probe.set_time(0.999)
	h.eq(probe.clock_text(), "05:59", "just before sunrise reads 05:59")
	probe.set_time(0.9999)
	h.eq(probe.clock_text(), "06:00", "a minute fraction before sunrise rounds up to 06:00")

	# --- phases --------------------------------------------------------------
	probe.set_time(0.25)
	h.eq(probe.phase_name(), "Day", "noon is called day")
	probe.set_time(0.75)
	h.eq(probe.phase_name(), "Night", "midnight is called night")
	probe.set_time(0.02)
	h.eq(probe.phase_name(), "Dawn", "just after sunrise is dawn")
	probe.set_time(0.48)
	h.eq(probe.phase_name(), "Dusk", "just before sunset is dusk")

	# --- determinism: the same time always produces the same lighting --------
	var first := DayNight.new(0.31, 60.0)
	var second := DayNight.new(0.0, 60.0)
	second.set_time(0.31)
	h.eq(first.sun_angles(), second.sun_angles(), "identical times give identical sun angles")
	h.eq(first.sun_energy(), second.sun_energy(), "identical times give identical sun energy")
	h.eq(first.sky_top_color(), second.sky_top_color(), "identical times give identical sky colours")
	h.eq(first.fog_color(), second.fog_color(), "identical times give identical fog colours")
	h.eq(first.clock_text(), second.clock_text(), "identical times give identical clock text")

	# --- sun angles stay sane -----------------------------------------------
	probe.set_time(0.25)
	var angles := probe.sun_angles()
	h.approx(angles.x, -DayNight.NOON_ELEVATION, 1e-5, "the noon zenith angle points the sun down onto the world")
	h.check(absf(angles.y) <= 360.0, "the sun azimuth stays in one turn")
	probe.set_time(0.75)
	h.approx(probe.sun_angles().x, -DayNight.NIGHT_LIGHT_ELEVATION, 1e-5,
		"at midnight the light is clamped above the horizon (moonlight, never lit from below)")
	h.check(probe.sun_angles().x < 0.0, "the night light still points downwards")

	# --- the sky's lower hemisphere and the water follow the clock ----------
	var night_ground := DayNight.new(0.75)
	var day_ground := DayNight.new(0.25)
	h.greater(day_ground.ground_horizon_color().get_luminance(), night_ground.ground_horizon_color().get_luminance(),
		"the ground half of the sky is darker at night")
	h.greater(day_ground.ground_bottom_color().get_luminance(), night_ground.ground_bottom_color().get_luminance(),
		"the lower ground colour darkens too")
	h.greater(day_ground.water_tint().get_luminance(), night_ground.water_tint().get_luminance(),
		"the water tint is dimmer at night")
	h.eq(night_ground.ground_horizon_color(), DayNight.NIGHT_GROUND_HORIZON, "midnight uses the night ground colour")
	h.eq(night_ground.water_tint(), DayNight.NIGHT_WATER_TINT, "midnight uses the night water tint")

	# --- the ambient fill must not be taken from a black night sky ----------
	h.less(night_ground.ambient_sky_contribution(), day_ground.ambient_sky_contribution(),
		"less of the night ambient comes from the (black) sky")
	h.less(night_ground.ambient_sky_contribution(), 0.5, "at night the fill light is mostly its own colour")
	h.eq(night_ground.ambient_color(), DayNight.NIGHT_AMBIENT, "midnight uses the night ambient colour")
	h.greater(night_ground.ambient_color().get_luminance(), 0.0, "the night ambient colour is not black")
	h.greater(day_ground.ambient_energy(), night_ground.ambient_energy(), "day ambient energy is higher than night")

	# The twilight window is wide enough to be visible at both ends.
	h.greater(DayNight.TWILIGHT, 0.0, "the twilight window has a positive width")
	var dawn := DayNight.new(0.0)
	h.eq(dawn.phase_name(), "Dawn", "sunrise is inside the twilight window")
	h.check(not dawn.is_night(), "sunrise is not classified as night")
	var just_after: DayNight = DayNight.new(0.53)
	h.check(not just_after.is_night(), "just after sunset is still twilight, not night")

	# --- save round-trip ----------------------------------------------------
	var payload: Dictionary = first.to_dictionary()
	var restored := DayNight.new(0.0, 1.0)
	h.check(restored.from_dictionary(payload), "the clock restores from its save payload")
	h.approx(restored.time_of_day, first.time_of_day, 1e-9, "the restored time matches")
	h.approx(restored.day_length_seconds, first.day_length_seconds, 1e-9, "the restored day length matches")
	var broken := DayNight.new(0.5)
	h.check(not broken.from_dictionary({"time_of_day": "noon"}), "a non-numeric time is rejected")
	h.approx(broken.time_of_day, 0.5, 1e-9, "a rejected payload leaves the clock untouched")
	h.check(not broken.from_dictionary({}), "a payload without a time is rejected")
	broken.from_dictionary({"time_of_day": 2.5})
	h.approx(broken.time_of_day, 0.5, 1e-9, "a restored out-of-range time wraps")

	h.finish()

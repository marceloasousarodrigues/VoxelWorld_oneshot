extends RefCounted

## Configuration model: defaults, clamping and a lossless dictionary round-trip.
## Pure data, so the rules are testable without the interface.

const SettingsModel = preload("res://scripts/core/game_settings.gd")


func name() -> String:
	return "game settings"


func run(h: TestHarness) -> void:
	h.section("game settings model")
	var settings = SettingsModel.new()
	h.eq(settings.render_distance, SettingsModel.RENDER_DISTANCE_DEFAULT, "render distance starts at its default")
	h.approx(settings.mouse_sensitivity, SettingsModel.SENSITIVITY_DEFAULT, 1e-9, "sensitivity starts at its default")
	h.check(settings.vsync, "vsync starts enabled")

	# Clamping on every setter.
	h.eq(settings.set_render_distance(99), SettingsModel.RENDER_DISTANCE_MAX, "an oversized render distance clamps to the maximum")
	h.eq(settings.set_render_distance(0), SettingsModel.RENDER_DISTANCE_MIN, "a tiny render distance clamps to the minimum")
	h.eq(settings.set_render_distance(6), 6, "a valid render distance is stored as given")
	h.approx(settings.set_mouse_sensitivity(10.0), SettingsModel.SENSITIVITY_MAX, 1e-9, "an oversized sensitivity clamps")
	h.approx(settings.set_mouse_sensitivity(-1.0), SettingsModel.SENSITIVITY_MIN, 1e-9, "a negative sensitivity clamps")
	h.approx(settings.set_mouse_sensitivity(0.003), 0.003, 1e-9, "a valid sensitivity is stored as given")
	settings.set_vsync(false)
	h.check(not settings.vsync, "vsync can be turned off")
	h.eq(settings.camera_mode, SettingsModel.CAMERA_MODE_FIRST, "the camera view starts in first person")
	h.approx(settings.camera_distance, SettingsModel.CAMERA_DISTANCE_DEFAULT, 1e-9, "the third-person distance starts at its default")
	h.approx(settings.camera_shoulder, SettingsModel.CAMERA_SHOULDER_DEFAULT, 1e-9, "the over-the-shoulder offset starts at its default")
	h.eq(settings.set_camera_mode("third_person"), SettingsModel.CAMERA_MODE_THIRD, "a valid camera mode is stored")
	h.eq(settings.set_camera_mode("nonsense"), SettingsModel.CAMERA_MODE_FIRST, "an unknown camera mode falls back to first person")
	settings.set_camera_mode("third_person")
	h.approx(settings.set_camera_distance(99.0), SettingsModel.CAMERA_DISTANCE_MAX, 1e-9, "an oversized camera distance clamps")
	h.approx(settings.set_camera_distance(0.0), SettingsModel.CAMERA_DISTANCE_MIN, 1e-9, "a tiny camera distance clamps")
	h.approx(settings.set_camera_distance(5.5), 5.5, 1e-9, "a valid camera distance is stored as given")
	h.approx(settings.set_camera_shoulder(9.0), SettingsModel.CAMERA_SHOULDER_MAX, 1e-9, "an oversized shoulder offset clamps")
	h.approx(settings.set_camera_shoulder(-1.0), SettingsModel.CAMERA_SHOULDER_MIN, 1e-9, "a negative shoulder offset clamps")
	h.approx(settings.set_camera_shoulder(0.85), 0.85, 1e-9, "a valid shoulder offset is stored as given")

	# Dictionary round-trip.
	var payload: Dictionary = settings.to_dictionary()
	h.eq(int(payload["render_distance"]), 6, "the payload carries the render distance")
	h.approx(float(payload["mouse_sensitivity"]), 0.003, 1e-9, "the payload carries the sensitivity")
	h.eq(bool(payload["vsync"]), false, "the payload carries the vsync flag")
	h.eq(str(payload["camera_mode"]), SettingsModel.CAMERA_MODE_THIRD, "the payload carries the camera mode")
	h.approx(float(payload["camera_distance"]), 5.5, 1e-9, "the payload carries the camera distance")
	h.approx(float(payload["camera_shoulder"]), 0.85, 1e-9, "the payload carries the shoulder offset")
	var restored = SettingsModel.new()
	h.check(restored.from_dictionary(payload), "the settings restore from their payload")
	h.eq(restored.render_distance, settings.render_distance, "the restored render distance matches")
	h.approx(restored.mouse_sensitivity, settings.mouse_sensitivity, 1e-9, "the restored sensitivity matches")
	h.eq(restored.vsync, settings.vsync, "the restored vsync flag matches")
	h.eq(restored.camera_mode, settings.camera_mode, "the restored camera mode matches")
	h.approx(restored.camera_distance, settings.camera_distance, 1e-9, "the restored camera distance matches")
	h.approx(restored.camera_shoulder, settings.camera_shoulder, 1e-9, "the restored shoulder offset matches")

	# Out-of-range payload values are clamped, not trusted.
	var clamped = SettingsModel.new()
	h.check(clamped.from_dictionary({"render_distance": 500, "mouse_sensitivity": 9.0}), "an out-of-range payload is accepted but clamped")
	h.eq(clamped.render_distance, SettingsModel.RENDER_DISTANCE_MAX, "a huge payload render distance clamps")
	h.approx(clamped.mouse_sensitivity, SettingsModel.SENSITIVITY_MAX, 1e-9, "a huge payload sensitivity clamps")

	# Garbage never corrupts live values.
	var safe = SettingsModel.new()
	var before := safe.to_dictionary()
	h.check(not safe.from_dictionary({"render_distance": "far", "mouse_sensitivity": {}, "vsync": "yes"}), "a non-numeric payload is rejected")
	h.eq(safe.to_dictionary(), before, "a rejected payload leaves the settings untouched")

	h.finish()

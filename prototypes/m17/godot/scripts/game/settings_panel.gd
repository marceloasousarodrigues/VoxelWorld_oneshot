class_name SettingsPanel
extends Control

## In-game configuration overlay: render distance, mouse sensitivity and vsync.
##
## Presentation and intent only -- it reads a `GameSettings` model to populate its
## controls and emits `setting_changed` when the player moves one.  The game layer
## owns applying the value (streamer, player, display) and persisting it.

signal setting_changed(key: String, value: Variant)

const GameSettingsModel = preload("res://scripts/core/game_settings.gd")
const PANEL_WIDTH := 460

var settings: GameSettingsModel

var _render_slider: HSlider
var _render_value: Label
var _sensitivity_slider: HSlider
var _sensitivity_value: Label
var _vsync_check: CheckButton
## Guards `refresh()` from re-emitting the change signal while it writes controls.
var _updating := false


func setup(game_settings: GameSettingsModel) -> void:
	settings = game_settings
	_build()
	refresh()
	visible = false


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.03, 0.05, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var box := PanelContainer.new()
	box.name = "Box"
	box.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	var box_style := StyleBoxFlat.new()
	box_style.bg_color = Color(0.05, 0.07, 0.1, 0.96)
	box_style.border_color = Color(1, 1, 1, 0.28)
	box_style.set_border_width_all(1)
	box_style.set_corner_radius_all(8)
	box.add_theme_stylebox_override("panel", box_style)
	center.add_child(box)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	box.add_child(margin)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	margin.add_child(list)

	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	list.add_child(title)

	var render_row := _build_slider_row(list, "Render distance",
		float(GameSettingsModel.RENDER_DISTANCE_MIN), float(GameSettingsModel.RENDER_DISTANCE_MAX), 1.0)
	_render_slider = render_row[0]
	_render_value = render_row[1]
	_render_slider.value_changed.connect(func(value: float) -> void:
		if not _updating:
			setting_changed.emit("render_distance", int(round(value))))

	var sensitivity_row := _build_slider_row(list, "Mouse sensitivity",
		GameSettingsModel.SENSITIVITY_MIN, GameSettingsModel.SENSITIVITY_MAX, 0.0001)
	_sensitivity_slider = sensitivity_row[0]
	_sensitivity_value = sensitivity_row[1]
	_sensitivity_slider.value_changed.connect(func(value: float) -> void:
		if not _updating:
			setting_changed.emit("mouse_sensitivity", value))

	var vsync_row := HBoxContainer.new()
	vsync_row.add_theme_constant_override("separation", 12)
	var vsync_label := Label.new()
	vsync_label.text = "Vertical sync"
	vsync_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vsync_label.add_theme_font_size_override("font_size", 16)
	vsync_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	vsync_row.add_child(vsync_label)
	_vsync_check = CheckButton.new()
	_vsync_check.toggled.connect(func(pressed: bool) -> void:
		if not _updating:
			setting_changed.emit("vsync", pressed))
	vsync_row.add_child(_vsync_check)
	list.add_child(vsync_row)

	var hint := Label.new()
	hint.text = "O or Esc closes  ·  saved to user://voxelworld_settings.cfg"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.68, 0.78, 0.88, 0.85))
	list.add_child(hint)


## Builds a label + slider + value readout row; returns [slider, value_label].
func _build_slider_row(parent: VBoxContainer, text: String, minimum: float, maximum: float, step: float) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(170, 0)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(200, 24)
	row.add_child(slider)
	var value := Label.new()
	value.custom_minimum_size = Vector2(58, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size", 14)
	value.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	row.add_child(value)
	parent.add_child(row)
	return [slider, value]


## Pushes the model into the controls without emitting `setting_changed`.
func refresh() -> void:
	if settings == null:
		return
	_updating = true
	_render_slider.value = settings.render_distance
	_render_value.text = str(settings.render_distance)
	_sensitivity_slider.value = settings.mouse_sensitivity
	_sensitivity_value.text = "%.4f" % settings.mouse_sensitivity
	_vsync_check.button_pressed = settings.vsync
	_updating = false


func open() -> void:
	refresh()
	visible = true


func close() -> void:
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func is_open() -> bool:
	return visible

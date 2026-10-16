class_name DeathScreen
extends Control

## Modal "you died" screen, shown on its own CanvasLayer above the HUD and below
## the pause menu.
##
## It is presentation and intent only: it shows the message and a Respawn button
## and emits `respawn_requested`.  The game layer owns the state change.  While it
## is open it stops mouse events, so it does not fight the other menus.

signal respawn_requested()

var _root: Control
var _cause: Label
var _respawn_button: Button


func _ready() -> void:
	_build()
	visible = false


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_root = Control.new()
	_root.name = "DeathRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.17, 0.0, 0.0, 0.74)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := Label.new()
	title.text = "YOU DIED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.95, 0.24, 0.24))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	box.add_child(title)

	_cause = Label.new()
	_cause.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cause.add_theme_font_size_override("font_size", 16)
	_cause.add_theme_color_override("font_color", Color(0.9, 0.78, 0.78))
	box.add_child(_cause)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	box.add_child(spacer)

	var button := Button.new()
	button.text = "Respawn"
	button.custom_minimum_size = Vector2(220, 44)
	button.pressed.connect(func() -> void: respawn_requested.emit())
	box.add_child(button)
	_respawn_button = button


func show_death(cause: String = "") -> void:
	_cause.text = "" if cause.is_empty() else "Cause: %s" % cause.capitalize()
	visible = true
	if _respawn_button != null:
		_respawn_button.grab_focus()


func hide_death() -> void:
	visible = false


func is_open() -> bool:
	return visible

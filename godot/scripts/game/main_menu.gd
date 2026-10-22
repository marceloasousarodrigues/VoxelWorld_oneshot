class_name MainMenu
extends CanvasLayer

## Title screen and pause menu.  Emits intent; it never touches world state.

signal new_world_requested(seed_value: int)
signal continue_requested()
signal quit_requested()
signal resume_requested()

var _root: Control
var _panel: VBoxContainer
var _title: Label
var _subtitle: Label
var _buttons: VBoxContainer
var _seed_field: LineEdit
var _save_note: Label


func _ready() -> void:
	layer = 20
	_build()
	# The menu starts hidden; the game shows it in menu or pause state.
	_root.visible = false


func _build() -> void:
	_root = Control.new()
	_root.name = "MenuRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0.042, 0.06, 0.086, 0.94)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(background)
	add_child(_root)

	_panel = VBoxContainer.new()
	_panel.name = "Panel"
	_panel.add_theme_constant_override("separation", 12)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.offset_left = -230
	_panel.offset_right = 230
	_panel.offset_top = -190
	_panel.offset_bottom = 210
	_root.add_child(_panel)

	_title = Label.new()
	_title.text = "VOXELWORLD"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 46)
	_title.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_title.add_theme_constant_override("shadow_offset_x", 2)
	_title.add_theme_constant_override("shadow_offset_y", 2)
	_panel.add_child(_title)

	_subtitle = Label.new()
	_subtitle.text = "Godot 4 native voxel build"
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", 15)
	_subtitle.add_theme_color_override("font_color", Color(0.72, 0.82, 0.9))
	_panel.add_child(_subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	_panel.add_child(spacer)

	var seed_row := HBoxContainer.new()
	seed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	seed_row.add_theme_constant_override("separation", 8)
	var seed_label := Label.new()
	seed_label.text = "World seed"
	seed_label.add_theme_font_size_override("font_size", 14)
	seed_label.add_theme_color_override("font_color", Color(0.78, 0.86, 0.93))
	seed_row.add_child(seed_label)
	_seed_field = LineEdit.new()
	_seed_field.text = "17017"
	_seed_field.custom_minimum_size = Vector2(140, 30)
	_seed_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	seed_row.add_child(_seed_field)
	_panel.add_child(seed_row)

	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 8)
	_panel.add_child(_buttons)

	_save_note = Label.new()
	_save_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_save_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_save_note.add_theme_font_size_override("font_size", 12)
	_save_note.add_theme_color_override("font_color", Color(0.68, 0.76, 0.84))
	_save_note.custom_minimum_size = Vector2(400, 34)
	_panel.add_child(_save_note)


func _add_button(text: String, callback: Callable, disabled: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 38)
	button.disabled = disabled
	button.pressed.connect(callback)
	_buttons.add_child(button)
	return button


func show_menu(has_save: bool, save_note: String) -> void:
	for child in _buttons.get_children():
		child.queue_free()
	_save_note.text = save_note
	_seed_field.visible = true
	_title.text = "VOXELWORLD"
	_add_button("New world", _on_new_world)
	_add_button("Continue saved world", _on_continue, not has_save)
	_add_button("Quit", _on_quit)
	_root.visible = true
	if has_save:
		_buttons.get_child(1).grab_focus()


func show_pause() -> void:
	for child in _buttons.get_children():
		child.queue_free()
	_seed_field.visible = false
	_save_note.text = "Your world is saved automatically; F5 saves immediately."
	_title.text = "PAUSED"
	_add_button("Resume", _on_resume)
	_add_button("Save now", _on_save)
	_add_button("Quit to title", _on_quit_to_title)
	_root.visible = true
	_buttons.get_child(0).grab_focus()


func hide_menu() -> void:
	_root.visible = false


func is_open() -> bool:
	return _root.visible


func seed_value() -> int:
	var text := _seed_field.text.strip_edges()
	if not text.is_valid_int():
		return 17017
	return text.to_int()


# --- callbacks -----------------------------------------------------------

var _save_callback := Callable()
var _title_callback := Callable()


func set_save_callback(callback: Callable) -> void:
	_save_callback = callback


func set_title_callback(callback: Callable) -> void:
	_title_callback = callback


func _on_new_world() -> void:
	new_world_requested.emit(seed_value())


func _on_continue() -> void:
	continue_requested.emit()


func _on_quit() -> void:
	quit_requested.emit()


func _on_resume() -> void:
	resume_requested.emit()


func _on_save() -> void:
	if _save_callback.is_valid():
		_save_callback.call()


func _on_quit_to_title() -> void:
	if _title_callback.is_valid():
		_title_callback.call()

class_name CraftingPanel
extends Control

## In-game crafting interface.
##
## A simple functional overlay: it lists the fixed recipe set, disables the rows
## the player cannot afford right now, and performs a craft when a row's button
## is pressed.  It is presentation and intent only -- it reads the `Inventory`
## model and the `Crafting` rules and never mutates the voxel world.  The game
## layer observes the `crafted` signal to report the outcome.

signal crafted(result: Dictionary)

const PANEL_WIDTH := 420

var inventory: Inventory

var _rows: Array = []
var _title: Label
var _hint: Label


func setup(player_inventory: Inventory) -> void:
	inventory = player_inventory
	_build()
	if inventory != null and not inventory.changed.is_connected(_refresh):
		inventory.changed.connect(_refresh)
	visible = false
	_refresh()


# --- construction --------------------------------------------------------

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.03, 0.05, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# A CenterContainer keeps the content-sized box centred; anchoring a
	# zero-size PanelContainer directly to the screen centre would let it grow
	# down and right from the anchor instead.
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
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	box.add_child(margin)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	margin.add_child(list)

	_title = Label.new()
	_title.text = "CRAFTING"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	list.add_child(_title)

	for recipe in Crafting.recipes():
		list.add_child(_build_row(recipe))

	_hint = Label.new()
	_hint.text = "Click Craft to use ingredients  ·  C or Esc closes"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(0.68, 0.78, 0.88, 0.85))
	list.add_child(_hint)


func _build_row(recipe: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = Crafting.label(recipe)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	row.add_child(label)
	var button := Button.new()
	button.text = "Craft"
	button.custom_minimum_size = Vector2(84, 30)
	var index := _rows.size()
	button.pressed.connect(func() -> void: _on_craft_pressed(index))
	row.add_child(button)
	_rows.append({"label": label, "button": button, "recipe": recipe})
	return row


# --- state ---------------------------------------------------------------

func _refresh() -> void:
	if inventory == null:
		return
	for index in _rows.size():
		var row: Dictionary = _rows[index]
		var enabled: bool = Crafting.can_craft(inventory, row["recipe"])
		(row["button"] as Button).disabled = not enabled
		(row["label"] as Label).modulate = Color(1, 1, 1, 1.0) if enabled else Color(1, 1, 1, 0.45)


func _on_craft_pressed(index: int) -> void:
	if index < 0 or index >= _rows.size() or inventory == null:
		return
	var result: Dictionary = Crafting.craft(inventory, _rows[index]["recipe"])
	crafted.emit(result)
	_refresh()


func open() -> void:
	_refresh()
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

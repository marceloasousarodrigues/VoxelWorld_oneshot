class_name CraftingPanel
extends Control

## In-game crafting interface.
##
## A centred overlay that lists the whole recipe catalogue grouped by category and
## filtered by the stations the player can actually use.  Every row shows the
## output, its ingredients with have/need counts, whether the station is
## available, and why a recipe cannot be crafted right now; recipes that are ready
## are bright and carry active Craft / x5 buttons.
##
## It is presentation and intent only -- it reads the `Inventory` model and the
## `Crafting` rules and never mutates the voxel world.  The game layer observes
## the `crafted` signal to report the outcome and owns the station decision.

signal crafted(result: Dictionary)

const PANEL_WIDTH := 600
const LIST_HEIGHT := 430
const ICON_SIZE := 32
const ROW_HEIGHT := 46

## The number of copies the batch button asks for.
const BATCH_SIZE := 5

const STATUS_READY := Color(0.55, 0.92, 0.58)
const STATUS_MISSING := Color(0.95, 0.55, 0.52)
const STATUS_BLOCKED := Color(0.95, 0.78, 0.42)

var inventory: Inventory

var _rows: Array = []
var _filter_buttons: Dictionary = {}
var _title: Label
var _station_label: Label
var _hint: Label
var _list: VBoxContainer
var _station := Crafting.STATION_HAND
var _filter := ""


func setup(player_inventory: Inventory, texture_library: TextureLibrary = null) -> void:
	inventory = player_inventory
	_build(texture_library)
	if inventory != null and not inventory.changed.is_connected(_refresh):
		inventory.changed.connect(_refresh)
	visible = false
	_refresh()


## The best station the player currently has; the game layer decides it.
func set_station(station: String) -> void:
	if _station == station:
		return
	_station = station
	_refresh()


func station() -> String:
	return _station


# --- construction --------------------------------------------------------

func _build(texture_library: TextureLibrary) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.03, 0.05, 0.55)
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
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	box.add_child(margin)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	margin.add_child(list)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	_title = Label.new()
	_title.text = "CRAFTING"
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	header.add_child(_title)
	_station_label = Label.new()
	_station_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_station_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_station_label.add_theme_font_size_override("font_size", 14)
	_station_label.add_theme_color_override("font_color", Color(0.72, 0.85, 0.95))
	header.add_child(_station_label)
	list.add_child(header)

	list.add_child(_build_filters())

	var scroll := ScrollContainer.new()
	scroll.name = "Recipes"
	scroll.custom_minimum_size = Vector2(PANEL_WIDTH - 40, LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.add_child(scroll)

	_list = VBoxContainer.new()
	_list.name = "RecipeList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)

	for recipe: Dictionary in Crafting.recipes():
		_list.add_child(_build_row(recipe, texture_library))

	_hint = Label.new()
	_hint.text = "Click Craft for one · x%d for five · C or Esc closes" % BATCH_SIZE
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(0.68, 0.78, 0.88, 0.85))
	list.add_child(_hint)


## Category filter buttons ("All" plus every catalogue category).  A button group
## keeps exactly one selected and `_filter` mirrors it.
func _build_filters() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.name = "Filters"
	bar.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	var categories: Array = ["All"]
	categories.append_array(Crafting.categories())
	for category: String in categories:
		var button := Button.new()
		button.text = category
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 13)
		button.set_meta("category", category)
		button.pressed.connect(func() -> void: _set_filter(category))
		if category == "All":
			button.button_pressed = true
		bar.add_child(button)
		_filter_buttons[category] = button
	return bar


func _set_filter(category: String) -> void:
	_filter = "" if category == "All" else category
	_refresh()


func _build_row(recipe: Dictionary, texture_library: TextureLibrary) -> PanelContainer:
	var root := PanelContainer.new()
	root.name = "Recipe_%s" % str(recipe["id"])
	root.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.14, 0.85)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	root.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	root.add_child(row)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if texture_library != null:
		var output := int(recipe["output"])
		icon.texture = texture_library.icon(ItemDB.icon_key(output))
		var tint := ItemDB.icon_tint(output)
		icon.modulate = tint
	row.add_child(icon)

	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation", 0)
	row.add_child(text_column)

	var name_line := HBoxContainer.new()
	name_line.add_theme_constant_override("separation", 10)
	name_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := Label.new()
	name_label.text = "%d %s" % [int(recipe["output_count"]), ItemDB.name_of(int(recipe["output"]))]
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color(0.94, 0.97, 1.0))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_line.add_child(name_label)
	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.add_theme_font_size_override("font_size", 13)
	name_line.add_child(status)
	text_column.add_child(name_line)

	var detail := Label.new()
	detail.add_theme_font_size_override("font_size", 12)
	detail.add_theme_color_override("font_color", Color(0.72, 0.78, 0.86, 0.9))
	text_column.add_child(detail)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	var craft := Button.new()
	craft.text = "Craft"
	craft.custom_minimum_size = Vector2(72, 30)
	craft.focus_mode = Control.FOCUS_NONE
	craft.pressed.connect(func() -> void: _craft(recipe, 1))
	buttons.add_child(craft)
	var batch := Button.new()
	batch.text = "x%d" % BATCH_SIZE
	batch.custom_minimum_size = Vector2(46, 30)
	batch.focus_mode = Control.FOCUS_NONE
	batch.pressed.connect(func() -> void: _craft(recipe, BATCH_SIZE))
	buttons.add_child(batch)
	row.add_child(buttons)

	_rows.append({
		"recipe": recipe, "root": root, "icon": icon, "name": name_label,
		"status": status, "detail": detail, "craft": craft, "batch": batch,
	})
	return root


# --- state ---------------------------------------------------------------

func _refresh() -> void:
	if inventory == null:
		return
	_station_label.text = "Station: %s" % _station_name(_station)
	var ready := 0
	var shown := 0
	for entry: Dictionary in _rows:
		var recipe: Dictionary = entry["recipe"]
		var visible := _filter.is_empty() or str(recipe["category"]) == _filter
		(entry["root"] as Control).visible = visible
		if not visible:
			continue
		shown += 1
		if _refresh_row(entry):
			ready += 1
	_hint.text = "Click Craft for one · x%d for five · %d of %d recipes ready · C or Esc closes" % [
		BATCH_SIZE, ready, shown]


## Updates one row from the current inventory and station.  Returns true when the
## recipe is ready to craft.
func _refresh_row(entry: Dictionary) -> bool:
	var recipe: Dictionary = entry["recipe"]
	var station_ok := Crafting.station_satisfied(recipe, _station)
	var missing: Dictionary = Crafting.missing(inventory, recipe, _station)
	var can_craft := Crafting.can_craft(inventory, recipe, _station)
	var batchable := Crafting.can_craft_times(inventory, recipe, BATCH_SIZE, _station)

	var status_text := ""
	var status_colour := STATUS_READY
	if not station_ok:
		status_text = "needs %s" % _station_name(Crafting.station_of(recipe))
		status_colour = STATUS_BLOCKED
	elif not missing.is_empty():
		status_text = "missing %s" % _shortfall(missing)
		status_colour = STATUS_MISSING
	elif not can_craft:
		status_text = "inventory full"
		status_colour = STATUS_BLOCKED
	else:
		status_text = "ready" if can_craft else ""
	(entry["status"] as Label).text = status_text
	(entry["status"] as Label).add_theme_color_override("font_color", status_colour)
	(entry["detail"] as Label).text = _detail_text(recipe)
	var craft_button := entry["craft"] as Button
	var batch_button := entry["batch"] as Button
	craft_button.disabled = not can_craft
	batch_button.disabled = not batchable
	var dim := Color(1, 1, 1, 1.0 if can_craft else 0.5)
	(entry["root"] as Control).modulate = dim
	(entry["icon"] as TextureRect).modulate = ItemDB.icon_tint(int(recipe["output"])) * dim
	return can_craft


## "1 Oak Log (1/2) + 1 Coal (0/1)" -- ingredients first, then the fuel.
func _detail_text(recipe: Dictionary) -> String:
	var parts: Array = []
	var ingredients := Crafting.ingredients(recipe)
	var keys: Array = ingredients.keys()
	keys.sort()
	for item_id in keys:
		parts.append("%d %s (%d/%d)" % [
			int(ingredients[item_id]), ItemDB.name_of(int(item_id)),
			mini(inventory.count_of(int(item_id)), int(ingredients[item_id])), int(ingredients[item_id])])
	var fuel_items := Crafting.fuel(recipe)
	var fuel_keys: Array = fuel_items.keys()
	fuel_keys.sort()
	for item_id in fuel_keys:
		parts.append("fuel %d %s (%d/%d)" % [
			int(fuel_items[item_id]), ItemDB.name_of(int(item_id)),
			mini(inventory.count_of(int(item_id)), int(fuel_items[item_id])), int(fuel_items[item_id])])
	parts.append(str(recipe["category"]))
	var station := Crafting.station_of(recipe)
	var extra := ""
	if station != Crafting.STATION_HAND:
		extra = "  ·  needs %s" % _station_name(station)
	return "%s%s" % ["  ·  ".join(parts), extra]


func _shortfall(missing: Dictionary) -> String:
	var parts: Array = []
	var keys: Array = missing.keys()
	keys.sort()
	for item_id in keys:
		parts.append("%d more %s" % [int(missing[item_id]), ItemDB.name_of(int(item_id))])
	return " + ".join(parts)


func _station_name(station: String) -> String:
	match station:
		Crafting.STATION_TABLE:
			return "Crafting Table"
		Crafting.STATION_FURNACE:
			return "Furnace"
	return "hand crafting"


func _craft(recipe: Dictionary, count: int) -> void:
	if inventory == null:
		return
	var result: Dictionary = Crafting.craft_many(inventory, recipe, count, _station)
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


## Diagnostic accessors (used by the runtime integration test).
func row_count() -> int:
	return _rows.size()


func visible_row_count() -> int:
	var count := 0
	for entry: Dictionary in _rows:
		if (entry["root"] as Control).visible:
			count += 1
	return count


func row_status(id: String) -> String:
	for entry: Dictionary in _rows:
		if str((entry["recipe"] as Dictionary)["id"]) == id:
			return (entry["status"] as Label).text
	return ""


func row_enabled(id: String) -> bool:
	for entry: Dictionary in _rows:
		if str((entry["recipe"] as Dictionary)["id"]) == id:
			return not (entry["craft"] as Button).disabled
	return false


## Diagnostic: activates a row's *real* button so the panel's own handler (and the
## `crafted` signal) runs, exactly as a mouse click would.  Returns false when the
## button is disabled.
func press_craft(id: String, batch: bool = false) -> bool:
	for entry: Dictionary in _rows:
		if str((entry["recipe"] as Dictionary)["id"]) != id:
			continue
		var button := (entry["batch"] if batch else entry["craft"]) as Button
		if button.disabled:
			return false
		button.pressed.emit()
		return true
	return false


## Puts the overlay into a small deterministic state for a screenshot: show every
## category so the catalogue is legible.
func show_all_variants() -> void:
	_filter = ""
	for category: String in _filter_buttons:
		(_filter_buttons[category] as Button).button_pressed = category == "All"
	_refresh()

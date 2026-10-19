class_name StationPanel
extends Control

## The world-object station interface (M19).
##
## One overlay serves every station kind.  It draws the station's own slots (a
## 3x3 grid and result for a crafting table; input, fuel and output for a
## furnace) next to the player's hotbar, and lets stacks move between the two
## inventories with click-to-carry, right-click split, shift-click quick-move and
## Godot drag & drop.
##
## Presentation and intent only: every mutation goes through `Station` /
## `StationInventory` / `Inventory`, so the interface can never invent items.  The
## game layer owns the station's world identity and reports outcomes.
##
## The crafting grid and the furnace contents are *persistent station storage*:
## closing the interface leaves them in the station.  A carried stack is returned
## to the player (and then to the station) on close, so no item is ever lost.

signal message(text: String)

const PANEL_WIDTH := 760
const ARROW_TEXT := "\u2192"

var inventory: Inventory
var station: Station
var library: TextureLibrary

var _carried: Dictionary = {}
var _station_slots: Array[StationSlot] = []
var _player_slots: Array[StationSlot] = []
var _station_area: VBoxContainer
var _player_row: HBoxContainer
var _carry_slot: StationSlot
var _carry_label: Label
var _title: Label
var _station_info: Label
var _status: Label
var _hint: Label
var _cook_fill: ColorRect
var _fuel_fill: ColorRect
var _cook_bar_width := 160.0
var _fuel_bar_width := 160.0


func setup(player_inventory: Inventory, texture_library: TextureLibrary = null) -> void:
	inventory = player_inventory
	library = texture_library
	_build()
	if inventory != null and not inventory.changed.is_connected(_refresh):
		inventory.changed.connect(_refresh)
	visible = false


# --- construction --------------------------------------------------------

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.03, 0.05, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.1, 0.97)
	style.border_color = Color(1, 1, 1, 0.28)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	box.add_theme_stylebox_override("panel", style)
	center.add_child(box)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	box.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	_title = _label(22, Color(0.95, 0.98, 1.0))
	_title.text = "STATION"
	header.add_child(_title)
	_station_info = _label(13, Color(0.72, 0.85, 0.95))
	_station_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_station_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_station_info)
	column.add_child(header)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 22)
	column.add_child(content)

	_station_area = VBoxContainer.new()
	_station_area.name = "StationSlots"
	_station_area.add_theme_constant_override("separation", 8)
	content.add_child(_station_area)

	var facts := PanelContainer.new()
	facts.custom_minimum_size = Vector2(240, 0)
	var facts_style := StyleBoxFlat.new()
	facts_style.bg_color = Color(0.07, 0.09, 0.13, 0.9)
	facts_style.set_corner_radius_all(5)
	facts_style.set_content_margin_all(12)
	facts.add_theme_stylebox_override("panel", facts_style)
	content.add_child(facts)
	var facts_column := VBoxContainer.new()
	facts_column.add_theme_constant_override("separation", 8)
	facts.add_child(facts_column)
	_status = _label(14, Color(0.88, 0.93, 0.99))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(214, 0)
	facts_column.add_child(_status)

	var separator := HSeparator.new()
	facts_column.add_child(separator)
	column.add_child(HSeparator.new())

	var player_title := _label(13, Color(0.7, 0.8, 0.9, 0.9))
	player_title.text = "PLAYER INVENTORY"
	column.add_child(player_title)

	_player_row = HBoxContainer.new()
	_player_row.name = "PlayerSlots"
	_player_row.add_theme_constant_override("separation", 6)
	column.add_child(_player_row)
	for index in Inventory.HOTBAR_SIZE:
		var slot := StationSlot.new()
		slot.configure("player", index, inventory, library)
		slot.clicked.connect(_on_slot_clicked)
		slot.stack_moved.connect(_on_stack_moved)
		_player_row.add_child(slot)
		_player_slots.append(slot)

	var carry_row := HBoxContainer.new()
	carry_row.add_theme_constant_override("separation", 10)
	column.add_child(carry_row)
	var carry_title := _label(13, Color(0.7, 0.8, 0.9, 0.9))
	carry_title.text = "CARRYING"
	carry_row.add_child(carry_title)
	_carry_slot = StationSlot.new()
	_carry_slot.configure("carry", -1, inventory, library)
	_carry_slot.custom_minimum_size = Vector2(StationSlot.SIZE, StationSlot.SIZE)
	carry_row.add_child(_carry_slot)
	_carry_label = _label(14, Color(0.92, 0.96, 1.0))
	carry_row.add_child(_carry_label)

	_hint = _label(12, Color(0.68, 0.78, 0.88, 0.85))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_hint)

	_refresh()


func _label(size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	return label


# --- opening / layout ----------------------------------------------------

func open_station(target: Station) -> void:
	if target == null:
		return
	if station != null and station.inventory.changed.is_connected(_refresh):
		station.inventory.changed.disconnect(_refresh)
	station = target
	_carried = {}
	if not station.inventory.changed.is_connected(_refresh):
		station.inventory.changed.connect(_refresh)
	_rebuild_station_area()
	visible = true
	_refresh()


func is_open() -> bool:
	return visible


## Public refresh hook: the game calls this when a furnace's timed state changed.
func refresh() -> void:
	_refresh()


func close() -> void:
	if not _carried.is_empty() and inventory != null:
		# A carried stack is returned to the player first; whatever does not fit
		# goes back into the station, so closing can never destroy an item.
		var leftover := _put("player", 0, _carried)
		var index := 1
		while not leftover.is_empty() and index < Inventory.HOTBAR_SIZE:
			leftover = _put("player", index, leftover)
			index += 1
		if not leftover.is_empty() and station != null:
			var remaining: int = station.inventory.deposit(leftover)
			leftover = {} if remaining <= 0 else {"item": int(leftover["item"]), "count": remaining}
		_carried = {}
	visible = false


func _rebuild_station_area() -> void:
	for child in _station_area.get_children():
		_station_area.remove_child(child)
		child.queue_free()
	_station_slots.clear()
	_cook_fill = null
	_fuel_fill = null
	if station == null:
		return
	if station.is_furnace():
		_build_furnace_area()
	else:
		_build_table_area()


func _build_table_area() -> void:
	_title.text = "CRAFTING TABLE"
	_station_info.text = "3×3 grid  ·  one item per cell"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_station_area.add_child(row)

	var grid_column := VBoxContainer.new()
	grid_column.add_theme_constant_override("separation", 6)
	row.add_child(grid_column)
	grid_column.add_child(_label(12, Color(0.7, 0.8, 0.9, 0.9)))
	var grid := GridContainer.new()
	grid.name = "CraftingGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	grid_column.add_child(grid)
	for index in Station.TABLE_GRID_SLOTS:
		var slot := _make_station_slot(index, "")
		grid.add_child(slot)

	var result_column := VBoxContainer.new()
	result_column.add_theme_constant_override("separation", 6)
	result_column.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(result_column)
	var arrow := _label(16, Color(0.7, 0.85, 0.95, 0.95))
	arrow.text = ARROW_TEXT
	result_column.add_child(arrow)
	var output := _make_station_slot(Station.TABLE_OUTPUT_SLOT, "result")
	result_column.add_child(output)

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	row.add_child(actions)
	var return_button := Button.new()
	return_button.name = "ReturnGrid"
	return_button.text = "Return grid"
	return_button.focus_mode = Control.FOCUS_NONE
	return_button.custom_minimum_size = Vector2(120, 32)
	return_button.pressed.connect(_on_return_grid)
	actions.add_child(return_button)
	var take_button := Button.new()
	take_button.name = "TakeResult"
	take_button.text = "Take result"
	take_button.focus_mode = Control.FOCUS_NONE
	take_button.custom_minimum_size = Vector2(120, 32)
	take_button.pressed.connect(take_output)
	actions.add_child(take_button)


func _build_furnace_area() -> void:
	_title.text = "FURNACE"
	_station_info.text = "input + fuel  ·  smelts over time"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_station_area.add_child(row)

	var input_column := VBoxContainer.new()
	input_column.add_theme_constant_override("separation", 6)
	row.add_child(input_column)
	var smelting_label := _label(12, Color(0.7, 0.8, 0.9, 0.9))
	smelting_label.text = "SMELTING"
	input_column.add_child(smelting_label)
	input_column.add_child(_make_station_slot(Station.FURNACE_INPUT_SLOT, "input"))
	input_column.add_child(_make_station_slot(Station.FURNACE_FUEL_SLOT, "fuel"))

	var progress_column := VBoxContainer.new()
	progress_column.add_theme_constant_override("separation", 10)
	progress_column.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(progress_column)
	var arrow := _label(16, Color(0.7, 0.85, 0.95, 0.95))
	arrow.text = ARROW_TEXT
	progress_column.add_child(arrow)
	var cook_label := _label(12, Color(0.75, 0.85, 0.95, 0.9))
	cook_label.text = "COOK"
	progress_column.add_child(cook_label)
	_cook_fill = _bar(progress_column, Color(0.96, 0.78, 0.35, 0.95))
	var fuel_label := _label(12, Color(0.75, 0.85, 0.95, 0.9))
	fuel_label.text = "FUEL"
	progress_column.add_child(fuel_label)
	_fuel_fill = _bar(progress_column, Color(0.95, 0.52, 0.24, 0.95))

	var output_column := VBoxContainer.new()
	output_column.add_theme_constant_override("separation", 6)
	output_column.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(output_column)
	var output_label := _label(12, Color(0.7, 0.8, 0.9, 0.9))
	output_label.text = "OUTPUT"
	output_column.add_child(output_label)
	output_column.add_child(_make_station_slot(Station.FURNACE_OUTPUT_SLOT, "output"))
	var take_button := Button.new()
	take_button.name = "TakeResult"
	take_button.text = "Take"
	take_button.focus_mode = Control.FOCUS_NONE
	take_button.custom_minimum_size = Vector2(100, 30)
	take_button.pressed.connect(take_output)
	output_column.add_child(take_button)


## A thin bar with a background, returning the fill rectangle the panel resizes.
func _bar(parent: Control, colour: Color) -> ColorRect:
	var root := Control.new()
	root.custom_minimum_size = Vector2(_cook_bar_width, 10)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(root)
	var background := ColorRect.new()
	background.color = Color(0.03, 0.04, 0.06, 0.8)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)
	var fill := ColorRect.new()
	fill.color = colour
	fill.size = Vector2(0, 10)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fill)
	return fill


func _make_station_slot(index: int, caption: String) -> StationSlot:
	var slot := StationSlot.new()
	slot.configure("station", index, station.inventory, library)
	slot.caption = caption
	slot.clicked.connect(_on_slot_clicked)
	slot.stack_moved.connect(_on_stack_moved)
	_station_slots.append(slot)
	return slot


# --- state ---------------------------------------------------------------

func _refresh() -> void:
	if visible == false and station == null:
		return
	for slot: StationSlot in _player_slots:
		slot.refresh()
	_carry_slot.override_stack = _carried
	_carry_slot.ghost = false
	_carry_slot.refresh()
	if _carried.is_empty():
		_carry_label.text = "nothing — click a stack to pick it up"
	else:
		_carry_label.text = "%d %s" % [int(_carried["count"]), ItemDB.name_of(int(_carried["item"]))]
	if station == null:
		return
	_refresh_station_slots()
	if station.is_furnace():
		_refresh_furnace()
	else:
		_refresh_table()
	_hint.text = "Left-click take/place · right-click split/place one · shift-click quick-move · drag a slot onto another · E or Esc closes"


func _refresh_station_slots() -> void:
	var preview: Dictionary = {}
	if not station.is_furnace() and station.inventory.is_empty(Station.TABLE_OUTPUT_SLOT):
		var result := station.result_preview()
		if not result.is_empty():
			preview = {"item": int(result["output"]), "count": int(result["count"])}
	for slot: StationSlot in _station_slots:
		var is_output := (not station.is_furnace() and slot.index == Station.TABLE_OUTPUT_SLOT) \
			or (station.is_furnace() and slot.index == Station.FURNACE_OUTPUT_SLOT)
		if is_output and not preview.is_empty():
			slot.override_stack = preview
			slot.ghost = true
		else:
			slot.override_stack = {}
			slot.ghost = false
		slot.refresh()


func _refresh_table() -> void:
	var result := station.result_preview()
	if result.is_empty():
		if station.inventory.total_items() == 0:
			_status.text = "Place ingredients in the 3×3 grid.\n\nThe result appears in the slot on the right; taking it consumes one item from every occupied cell."
		else:
			_status.text = "No matching recipe.\n\nCheck the shape: recipes are patterns in the grid, and an ingredient cannot share a cell with another."
	else:
		var recipe: Dictionary = result["recipe"]
		_status.text = "%s\n\n%s" % [
			"Ready: %d %s" % [int(result["count"]), ItemDB.name_of(int(result["output"]))],
			Crafting.label(recipe),
		]
	_station_info.text = "3×3 grid  ·  %d item%s in the grid" % [
		station.inventory.total_items(),
		"" if station.inventory.total_items() == 1 else "s"]


func _refresh_furnace() -> void:
	var input := station.inventory.item_at(Station.FURNACE_INPUT_SLOT)
	var recipe := Smelting.recipe_for(input)
	if not recipe.is_empty():
		_status.text = "Smelting %s → %d %s\n\nCook time %.1fs per item.  Fuel burns only while there is work and room for the output." % [
			ItemDB.name_of(input), int(recipe["output_count"]),
			ItemDB.name_of(int(recipe["output"])), Smelting.cook_seconds(recipe)]
	elif input != BlockDB.AIR:
		_status.text = "%s cannot be smelted here." % ItemDB.name_of(input)
	else:
		_status.text = "Put a smeltable item in the input and a fuel such as Coal or Planks in the fuel slot."
	if station.is_active():
		_status.text += "\n\nFurnace is %s." % ("cooking" if station.cook_progress > 0.0 else "burning")
	else:
		_status.text += "\n\nFurnace is idle."
	if _cook_fill != null:
		_cook_fill.size.x = _cook_bar_width * station.cook_ratio()
	if _fuel_fill != null:
		_fuel_fill.size.x = _fuel_bar_width * station.fuel_ratio()
	var fuel := station.inventory.item_at(Station.FURNACE_FUEL_SLOT)
	_station_info.text = "Fuel: %s  ·  %s" % [
		"none" if fuel == BlockDB.AIR else ItemDB.name_of(fuel),
		"active" if station.is_active() else "idle"]


# --- interactions --------------------------------------------------------

func _on_slot_clicked(side: String, index: int, button: int, shift: bool) -> void:
	if shift:
		quick_move(side, index)
		_refresh()
		return
	if button == MOUSE_BUTTON_RIGHT:
		if _carried.is_empty():
			pick_up_half(side, index)
		else:
			put_one(side, index)
		_refresh()
		return
	if not _carried.is_empty():
		put_down(side, index)
		_refresh()
		return
	if side == "station" and _is_output(index):
		take_output()
	else:
		pick_up(side, index)
	_refresh()


func _on_stack_moved(from_side: String, from_index: int, to_side: String, to_index: int) -> void:
	move_between(from_side, from_index, to_side, to_index)
	_refresh()


## Drag & drop: move one stack between two slots.  A target holding a different
## item is refused (rather than swapped across containers), and the station's
## result slot never accepts a player drop, so the operation is always a plain
## count-preserving move.
func move_between(from_side: String, from_index: int, to_side: String, to_index: int) -> bool:
	if from_side == to_side and from_index == to_index:
		return false
	if to_side == "station" and _is_output(to_index):
		return false
	var source = _model(from_side)
	var target = _model(to_side)
	if source == null or target == null:
		return false
	if source.is_empty(from_index):
		return false
	var item_id: int = source.item_at(from_index)
	if not target.is_empty(to_index) and target.item_at(to_index) != item_id:
		return false
	var stack := _take(from_side, from_index, -1)
	if stack.is_empty():
		return false
	var leftover := _restore(to_side, to_index, stack)
	if not leftover.is_empty():
		_restore(from_side, from_index, leftover)
	return true


func _is_output(index: int) -> bool:
	if station == null:
		return false
	if station.is_furnace():
		return index == Station.FURNACE_OUTPUT_SLOT
	return index == Station.TABLE_OUTPUT_SLOT


func _model(side: String) -> Variant:
	if side == "player":
		return inventory
	return station.inventory if station != null else null


## Takes a stack out of one side.  `amount < 0` takes the whole stack.
func _take(side: String, index: int, amount: int = -1) -> Dictionary:
	if side == "player":
		if inventory == null or inventory.is_empty(index):
			return {}
		if amount < 0:
			return inventory.take_stack(index)
		var whole := inventory.take_stack(index)
		if whole.is_empty():
			return {}
		var taken := mini(int(whole["count"]), amount)
		if taken < int(whole["count"]):
			# The slot is empty now, so the remainder always fits back into it.
			inventory.put_stack(index, {"item": int(whole["item"]),
				"count": int(whole["count"]) - taken, "durability": int(whole.get("durability", 0))})
		return {"item": int(whole["item"]), "count": taken,
			"durability": int(whole.get("durability", 0))}
	if station == null:
		return {}
	return station.inventory.take(index, amount)


## Puts a stack into one side, returning whatever did not fit.
func _put(side: String, index: int, stack: Dictionary) -> Dictionary:
	if stack.is_empty():
		return {}
	if side == "player":
		return inventory.put_stack(index, stack) if inventory != null else stack
	if station == null:
		return stack
	return station.inventory.insert(index, stack)


## Puts a stack back where it came from.  The result slots refuse player-facing
## inserts on purpose, so restoring to them needs the station's own permission.
func _restore(side: String, index: int, stack: Dictionary) -> Dictionary:
	if stack.is_empty():
		return {}
	if side == "station" and station != null:
		return station.inventory.insert(index, stack, _is_output(index))
	return _put(side, index, stack)


func pick_up(side: String, index: int) -> bool:
	if not _carried.is_empty():
		return false
	var stack := _take(side, index, -1)
	if stack.is_empty():
		return false
	_carried = stack
	return true


## Right-click with nothing carried: take about half of the stack.
func pick_up_half(side: String, index: int) -> bool:
	if not _carried.is_empty():
		return false
	var model = _model(side)
	if model == null or model.is_empty(index):
		return false
	var count: int = model.count_at(index)
	var half := maxi(1, int(ceil(float(count) * 0.5)))
	var stack := _take(side, index, half)
	if stack.is_empty():
		return false
	_carried = stack
	return true


func put_down(side: String, index: int) -> bool:
	if _carried.is_empty():
		return false
	_carried = _put(side, index, _carried)
	return true


## Right-click while carrying: place a single item.
func put_one(side: String, index: int) -> bool:
	if _carried.is_empty():
		return false
	var one := {"item": int(_carried["item"]), "count": 1,
		"durability": int(_carried.get("durability", 0))}
	var leftover := _put(side, index, one)
	if not leftover.is_empty():
		return false
	_carried["count"] = int(_carried["count"]) - 1
	if int(_carried["count"]) <= 0:
		_carried = {}
	return true


## Shift-click: move a whole stack to the other inventory wherever it fits.
func quick_move(side: String, index: int) -> bool:
	var stack := _take(side, index, -1)
	if stack.is_empty():
		return false
	var item_id := int(stack["item"])
	var count := int(stack["count"])
	var wear := int(stack.get("durability", 0))
	var leftover_count := 0
	if side == "player":
		if station == null:
			leftover_count = count
		else:
			leftover_count = station.inventory.deposit(stack)
	else:
		leftover_count = inventory.add(item_id, count, wear) if inventory != null else count
	if leftover_count > 0:
		# Put the remainder back where it came from.
		var remainder := {"item": item_id, "count": leftover_count, "durability": wear}
		_restore(side, index, remainder)
	return leftover_count < count


## Left-click on the result slot (or the Take button): craft one recipe on a
## table, then take the output.  A furnace result is simply taken.
func take_output() -> bool:
	if station == null:
		return false
	if not station.is_furnace() and station.inventory.is_empty(Station.TABLE_OUTPUT_SLOT):
		var crafted: Dictionary = station.craft_grid()
		if not bool(crafted["ok"]):
			message.emit(str(crafted.get("reason", "Cannot craft")))
			_refresh()
			return false
		message.emit("Crafted %d %s" % [int(crafted["count"]), ItemDB.name_of(int(crafted["output"]))])
	var index := Station.FURNACE_OUTPUT_SLOT if station.is_furnace() else Station.TABLE_OUTPUT_SLOT
	if station.inventory.is_empty(index):
		return false
	if not _carried.is_empty():
		message.emit("Place the carried stack first")
		return false
	_carried = _take("station", index, -1)
	_refresh()
	return true


func _on_return_grid() -> void:
	if station == null or station.is_furnace():
		return
	var returned := station.return_crafting_items(inventory)
	if returned > 0:
		message.emit("Returned %d item%s to your inventory" % [returned, "" if returned == 1 else "s"])
	else:
		message.emit("No room to return the grid — the items stay in the table")
	_refresh()


# --- diagnostics ---------------------------------------------------------

func carried() -> Dictionary:
	return _carried.duplicate()


func slot_count() -> int:
	return _station_slots.size() + _player_slots.size()


func station_slot_count() -> int:
	return _station_slots.size()


## Text of the facts/status pane, for diagnostics.
func status_text() -> String:
	return _status.text


## Activates the real "Take result" button, so a test drives the same path a
## mouse click does.
func press_take() -> bool:
	var button := _find_button("TakeResult")
	if button == null:
		return false
	button.pressed.emit()
	return true


func press_return_grid() -> bool:
	var button := _find_button("ReturnGrid")
	if button == null:
		return false
	button.pressed.emit()
	return true


func _find_button(node_name: String) -> Button:
	for child in find_children(node_name, "Button", true, false):
		return child as Button
	return null

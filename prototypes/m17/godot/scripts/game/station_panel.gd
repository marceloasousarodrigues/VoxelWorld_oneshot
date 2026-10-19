class_name StationPanel
extends Control

## The world-object station interface (M20).
##
## One overlay serves every station kind.  It draws the station's own slots (a
## 3x3 grid and result for a crafting table; input, fuel and output for a
## furnace) above the player's full 27+9 inventory, and lets stacks move between
## the two inventories with click-to-carry, right-click split, shift-click
## quick-move and Godot drag & drop.
##
## Presentation and intent only: every mutation goes through `Station` /
## `StationInventory` / `Inventory`, so the interface can never invent items.  The
## game layer owns the station's world identity and reports outcomes.
##
## The crafting grid and the furnace contents are persistent station storage:
## closing the interface leaves them in the station.  A temporary cursor stack is
## recovered into the player, then the station, on close, so no item is lost.

signal message(text: String)

const PANEL_WIDTH := 880
const ARROW_TEXT := "\u2192"
const DETAIL_WIDTH := 236

var inventory: Inventory
var station: Station
var library: TextureLibrary

var _carried: Dictionary = {}
var _carry_origin_side := ""
var _carry_origin_index := -1
var _station_slots: Array[StationSlot] = []
var _player_slots: Array[StationSlot] = []
var _station_area: VBoxContainer
var _player_main: GridContainer
var _player_hotbar: HBoxContainer
var _cursor: ItemCursor
var _title: Label
var _station_info: Label
var _status: Label
var _hint: Label
var _cook_fill: ColorRect
var _fuel_fill: ColorRect
var _cook_bar_width := 150.0
var _fuel_bar_width := 150.0


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
	dim.color = Color(0.02, 0.03, 0.05, 0.60)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	box.add_theme_stylebox_override("panel", UiStyle.panel_style())
	center.add_child(box)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	box.add_child(margin)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	margin.add_child(columns)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	_title = _label("STATION", 21, UiStyle.TEXT_PRIMARY)
	header.add_child(_title)
	_station_info = _label("", 13, UiStyle.TEXT_SECONDARY)
	_station_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_station_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_station_info)
	left.add_child(header)

	_station_area = VBoxContainer.new()
	_station_area.name = "StationSlots"
	_station_area.add_theme_constant_override("separation", 8)
	left.add_child(_station_area)

	left.add_child(HSeparator.new())
	var player_title := _label("PLAYER INVENTORY", 11, UiStyle.TEXT_MUTED)
	left.add_child(player_title)

	_player_main = GridContainer.new()
	_player_main.name = "PlayerMain"
	_player_main.columns = Inventory.HOTBAR_SIZE
	_player_main.add_theme_constant_override("h_separation", 5)
	_player_main.add_theme_constant_override("v_separation", 5)
	left.add_child(_player_main)
	for index in range(Inventory.MAIN_FIRST, Inventory.SIZE):
		_player_main.add_child(_make_player_slot(index))

	var hotbar_spacer := Control.new()
	hotbar_spacer.custom_minimum_size = Vector2(0, 7)
	left.add_child(hotbar_spacer)
	_player_hotbar = HBoxContainer.new()
	_player_hotbar.name = "PlayerHotbar"
	_player_hotbar.add_theme_constant_override("separation", 5)
	left.add_child(_player_hotbar)
	for index in Inventory.HOTBAR_SIZE:
		_player_hotbar.add_child(_make_player_slot(index))

	_hint = _label("", 12, UiStyle.TEXT_MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(570, 0)
	left.add_child(_hint)

	var facts := PanelContainer.new()
	facts.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	facts.add_theme_stylebox_override("panel", UiStyle.detail_style())
	columns.add_child(facts)
	var facts_column := VBoxContainer.new()
	facts_column.add_theme_constant_override("separation", 8)
	facts.add_child(facts_column)
	var facts_title := _label("STATION NOTES", 11, UiStyle.TEXT_MUTED)
	facts_column.add_child(facts_title)
	_status = _label("", 13, Color(0.88, 0.93, 0.99))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(DETAIL_WIDTH - 24, 0)
	facts_column.add_child(_status)
	var facts_spacer := Control.new()
	facts_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	facts_column.add_child(facts_spacer)
	var recipe_hint := _label("Recipes use the existing catalogue.\n"
		+ "Missing ingredients and a missing station are reported separately.", 11, UiStyle.TEXT_MUTED)
	recipe_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	facts_column.add_child(recipe_hint)

	_cursor = ItemCursor.new()
	_cursor.name = "CursorStack"
	add_child(_cursor)
	_cursor.setup(library)

	_refresh()


func _label(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	return label


func _make_player_slot(index: int) -> StationSlot:
	var slot := StationSlot.new()
	slot.name = "PlayerSlot%d" % index
	slot.configure("player", index, inventory, library)
	slot.clicked.connect(_on_slot_clicked)
	slot.stack_moved.connect(_on_stack_moved)
	_player_slots.append(slot)
	return slot


# --- opening / layout ----------------------------------------------------

func open_station(target: Station) -> void:
	if target == null:
		return
	if visible and not close():
		return
	if station != null and station.inventory.changed.is_connected(_refresh):
		station.inventory.changed.disconnect(_refresh)
	station = target
	_carried = {}
	_carry_origin_side = ""
	_carry_origin_index = -1
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


## Returns the temporary cursor stack to its origin, then the player, then the
## station, *without* closing the panel, so a save always contains every owned
## item.  Returns false when there is genuinely no room; the stack stays on the
## cursor (nothing is destroyed).
func flush_cursor() -> bool:
	if _carried.is_empty() or inventory == null:
		return true
	_carried = _recover_cursor()
	if _carried.is_empty():
		_carry_origin_side = ""
		_carry_origin_index = -1
	_cursor.set_stack(_carried)
	return _carried.is_empty()


## Closes the interface.  A cursor stack is returned to its origin, then to the
## player, then to the station; if every container is full the panel stays open
## and explains why, so nothing is silently deleted.  Returns true when closed.
func close() -> bool:
	if not _carried.is_empty() and inventory != null:
		var leftover := _recover_cursor()
		if not leftover.is_empty():
			_carried = leftover
			_cursor.set_stack(_carried)
			message.emit("No room for %d %s — make space before closing" % [
				int(_carried["count"]), ItemDB.name_of(int(_carried["item"]))])
			return false
		_carried = {}
		_carry_origin_side = ""
		_carry_origin_index = -1
	_cursor.set_stack({})
	# Drop the reference: a closed panel must not keep an orphaned station alive
	# or keep refreshing after its world object is gone.
	if station != null and station.inventory.changed.is_connected(_refresh):
		station.inventory.changed.disconnect(_refresh)
	station = null
	visible = false
	return true


func _recover_cursor() -> Dictionary:
	var leftover := _carried.duplicate()
	if _carry_origin_index >= 0:
		var model = _model(_carry_origin_side)
		if model != null and (_carry_origin_index < model.size() and
				(model.is_empty(_carry_origin_index)
				or model.item_at(_carry_origin_index) == int(leftover["item"]))):
			leftover = _restore(_carry_origin_side, _carry_origin_index, leftover)
	if not leftover.is_empty():
		leftover = inventory.add_stack(leftover)
	if not leftover.is_empty() and station != null:
		var remaining: int = station.inventory.deposit(leftover)
		if remaining <= 0:
			leftover = {}
		else:
			leftover = {"item": int(leftover["item"]), "count": remaining,
				"durability": int(leftover.get("durability", 0))}
	return leftover


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
	_station_info.text = "3×3 grid  ·  one ingredient per cell"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_station_area.add_child(row)

	var grid_column := VBoxContainer.new()
	grid_column.add_theme_constant_override("separation", 4)
	row.add_child(grid_column)
	grid_column.add_child(_label("CRAFTING GRID", 11, UiStyle.TEXT_MUTED))
	var grid := GridContainer.new()
	grid.name = "CraftingGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	grid_column.add_child(grid)
	for index in Station.TABLE_GRID_SLOTS:
		grid.add_child(_make_station_slot(index, ""))

	var result_column := VBoxContainer.new()
	result_column.add_theme_constant_override("separation", 4)
	result_column.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(result_column)
	var arrow := _label(ARROW_TEXT, 18, UiStyle.TEXT_SECONDARY)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_column.add_child(arrow)
	var output := _make_station_slot(Station.TABLE_OUTPUT_SLOT, "result")
	result_column.add_child(output)

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(actions)
	var return_button := Button.new()
	return_button.name = "ReturnGrid"
	return_button.text = "Return grid"
	return_button.focus_mode = Control.FOCUS_NONE
	return_button.custom_minimum_size = Vector2(124, 32)
	return_button.pressed.connect(_on_return_grid)
	actions.add_child(return_button)
	var take_button := Button.new()
	take_button.name = "TakeResult"
	take_button.text = "Take result"
	take_button.focus_mode = Control.FOCUS_NONE
	take_button.custom_minimum_size = Vector2(124, 32)
	take_button.pressed.connect(take_output)
	actions.add_child(take_button)


func _build_furnace_area() -> void:
	_title.text = "FURNACE"
	_station_info.text = "input + fuel  ·  smelts over time"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_station_area.add_child(row)

	var input_column := VBoxContainer.new()
	input_column.add_theme_constant_override("separation", 4)
	row.add_child(input_column)
	var smelting_label := _label("SMELTING", 11, UiStyle.TEXT_MUTED)
	smelting_label.text = "SMELTING"
	input_column.add_child(smelting_label)
	input_column.add_child(_make_station_slot(Station.FURNACE_INPUT_SLOT, "input"))
	input_column.add_child(_make_station_slot(Station.FURNACE_FUEL_SLOT, "fuel"))

	var progress_column := VBoxContainer.new()
	progress_column.add_theme_constant_override("separation", 8)
	progress_column.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(progress_column)
	var arrow := _label(ARROW_TEXT, 18, UiStyle.TEXT_SECONDARY)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_column.add_child(arrow)
	var cook_label := _label("COOK", 11, UiStyle.TEXT_MUTED)
	progress_column.add_child(cook_label)
	_cook_fill = _bar(progress_column, Color(0.96, 0.78, 0.35, 0.95))
	var fuel_label := _label("FUEL", 11, UiStyle.TEXT_MUTED)
	progress_column.add_child(fuel_label)
	_fuel_fill = _bar(progress_column, Color(0.95, 0.52, 0.24, 0.95))

	var output_column := VBoxContainer.new()
	output_column.add_theme_constant_override("separation", 4)
	output_column.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(output_column)
	var output_label := _label("OUTPUT", 11, UiStyle.TEXT_MUTED)
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
	if _status == null:
		return
	for slot: StationSlot in _player_slots:
		if slot.index < Inventory.HOTBAR_SIZE:
			slot.selected = slot.index == inventory.selected
		else:
			slot.selected = false
		slot.invalid = false
		slot.refresh()
	_cursor.set_stack(_carried)
	if station == null:
		if _hint != null:
			_hint.text = "E or Esc closes"
		return
	_refresh_station_slots()
	if station.is_furnace():
		_refresh_furnace()
	else:
		_refresh_table()
	_hint.text = "Left click: take/place · Right click: split/one · " \
		+ "Shift-click: quick-move · E/Esc closes"


func _refresh_station_slots() -> void:
	var preview: Dictionary = {}
	if not station.is_furnace() and station.inventory.is_empty(Station.TABLE_OUTPUT_SLOT):
		var result := station.result_preview()
		if not result.is_empty():
			preview = {"item": int(result["output"]), "count": int(result["count"])}
	for slot: StationSlot in _station_slots:
		var is_output := _is_output(slot.index)
		if is_output and not preview.is_empty():
			slot.override_stack = preview
			slot.ghost = true
		else:
			slot.override_stack = {}
			slot.ghost = false
		slot.invalid = _slot_rejects_carry(slot.index)
		slot.refresh()


func _slot_rejects_carry(index: int) -> bool:
	if _carried.is_empty() or station == null:
		return false
	var item_id := int(_carried["item"])
	if _is_output(index):
		return true
	if _is_grid_slot(index):
		return false
	return not station.inventory.accepts(index, item_id)


func _is_grid_slot(index: int) -> bool:
	return not station.is_furnace() and index >= 0 and index < Station.TABLE_GRID_SLOTS


func _refresh_table() -> void:
	var result := station.result_preview()
	var grid_items := station.inventory.total_items() - station.inventory.count_at(Station.TABLE_OUTPUT_SLOT)
	if result.is_empty():
		if grid_items == 0:
			_status.text = "Place ingredients in the 3×3 grid.\n\nClick a stack into a cell once per ingredient; the result appears on the right."
		else:
			_status.text = "No matching recipe.\n\nThe grid is a shape: one item per cell. Check the pattern, and remember that a stack in one cell counts as one ingredient there."
	else:
		var recipe: Dictionary = result["recipe"]
		_status.text = "Ready: %d %s\n\n%s" % [
			int(result["count"]), ItemDB.name_of(int(result["output"])),
			Crafting.label(recipe),
		]
		if not station.inventory.is_empty(Station.TABLE_OUTPUT_SLOT):
			_status.text += "\n\nTake the finished result before crafting again."
	_station_info.text = "3×3 grid  ·  %d item%s in the grid" % [
		grid_items, "" if grid_items == 1 else "s"]


func _refresh_furnace() -> void:
	var input := station.inventory.item_at(Station.FURNACE_INPUT_SLOT)
	var recipe := Smelting.recipe_for(input)
	if not recipe.is_empty():
		_status.text = "Smelting %s → %d %s\n\nCook time %.1fs per item. Fuel burns only while there is work and room for the output." % [
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
		# A crafting-grid cell takes one item per click; a player or furnace slot
		# takes the whole stack, like Minecraft.
		if side == "station" and _is_grid_slot(index):
			put_one(side, index)
		else:
			put_down(side, index)
		_refresh()
		return
	if side == "station" and _is_output(index):
		take_output()
	else:
		pick_up(side, index)
	_refresh()


func _on_stack_moved(from_side: String, from_index: int, to_side: String, to_index: int) -> void:
	if _carried.is_empty():
		move_between(from_side, from_index, to_side, to_index)
	_refresh()


## Drag & drop: move one stack between two slots.  A target holding a different
## item is refused, and the station's result slot never accepts a player drop, so
## the operation is always a plain count-preserving move.
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
	# A stack dragged from the player inventory into a crafting-grid cell places
	# one ingredient, matching the click and shift-click rules.  Otherwise a
	# four-plank stack would land in one cell and satisfy no recipe.
	if from_side == "player" and to_side == "station" and _is_grid_slot(to_index):
		var one := _take(from_side, from_index, 1)
		if one.is_empty():
			return false
		var one_left := _restore(to_side, to_index, one)
		if not one_left.is_empty():
			_restore(from_side, from_index, one_left)
			return false
		return true
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
	_carry_origin_side = side
	_carry_origin_index = index
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
	_carry_origin_side = side
	_carry_origin_index = index
	return true


func put_down(side: String, index: int) -> bool:
	if _carried.is_empty():
		return false
	var before_item := int(_carried["item"])
	_carried = _put(side, index, _carried)
	if _carried.is_empty():
		_carry_origin_side = ""
		_carry_origin_index = -1
	elif int(_carried["item"]) != before_item:
		# A swap displaced the target stack; it is now the cursor stack.
		_carry_origin_side = side
		_carry_origin_index = index
	return true


## Right-click while carrying: place a single item.  This never swaps a different
## item out of the target: an incompatible occupied slot refuses the operation
## before the model is touched, so the displaced stack cannot be dropped.
func put_one(side: String, index: int) -> bool:
	if _carried.is_empty():
		return false
	var model = _model(side)
	if model == null:
		return false
	if not model.is_empty(index) and model.item_at(index) != int(_carried["item"]):
		return false
	var one := {"item": int(_carried["item"]), "count": 1,
		"durability": int(_carried.get("durability", 0))}
	var leftover := _put(side, index, one)
	if not leftover.is_empty():
		return false
	_carried["count"] = int(_carried["count"]) - 1
	if int(_carried["count"]) <= 0:
		_carried = {}
		_carry_origin_side = ""
		_carry_origin_index = -1
	return true


## Shift-click: move a whole stack to the other inventory wherever it fits.
## For a crafting table, a player stack is spread one item per grid cell rather
## than dumped into one cell (which would make a 4-ingredient recipe unusable).
func quick_move(side: String, index: int) -> bool:
	var stack := _take(side, index, -1)
	if stack.is_empty():
		return false
	var item_id := int(stack["item"])
	var count := int(stack["count"])
	var wear := int(stack.get("durability", 0))
	var leftover_count := count
	if side == "player":
		if station == null:
			leftover_count = count
		elif station.is_furnace():
			leftover_count = station.inventory.deposit(stack)
		else:
			leftover_count = _deposit_to_grid(stack)
	else:
		var leftover := inventory.add_stack(stack) if inventory != null else stack
		# `add_stack` returns an empty dictionary when everything fit.  Do not use
		# the original count as a default here: that made a successful station ->
		# player shift-click restore the whole stack to the station as well,
		# duplicating it in both containers.
		leftover_count = 0 if leftover.is_empty() else int(leftover.get("count", 0))
	if leftover_count > 0:
		# Put the remainder back where it came from.
		var remainder := {"item": item_id, "count": leftover_count, "durability": wear}
		_restore(side, index, remainder)
	return leftover_count < count


## Spreads a stack across the 3x3 grid, one item per cell per pass.  Returns the
## number of items that did not fit, so the caller can restore them.
func _deposit_to_grid(stack: Dictionary) -> int:
	var carried := stack.duplicate()
	var remaining := int(carried.get("count", 0))
	var item_id := int(carried.get("item", BlockDB.AIR))
	var wear := int(carried.get("durability", 0))
	var moved := true
	while remaining > 0 and moved:
		moved = false
		for grid_index in Station.TABLE_GRID_SLOTS:
			if remaining <= 0:
				break
			if not station.inventory.is_empty(grid_index) \
					and station.inventory.item_at(grid_index) != item_id:
				continue
			var one := {"item": item_id, "count": 1, "durability": wear}
			var leftover := station.inventory.insert(grid_index, one)
			if leftover.is_empty():
				remaining -= 1
				moved = true
	return remaining


## Left-click on the result slot (or the Take button): craft one recipe on a
## table, then take the output.  A furnace result is simply taken.
func take_output() -> bool:
	if station == null:
		return false
	if not _carried.is_empty():
		message.emit("Place the cursor stack first")
		_refresh()
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
	_carried = _take("station", index, -1)
	_carry_origin_side = "station"
	_carry_origin_index = index
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


## Diagnostic/test entry: runs the same handler a real slot click uses.
func click_slot(side: String, index: int, button: int = MOUSE_BUTTON_LEFT,
		shift: bool = false) -> void:
	_on_slot_clicked(side, index, button, shift)


func slot_count() -> int:
	return _station_slots.size() + _player_slots.size()


func station_slot_count() -> int:
	return _station_slots.size()


## Text of the facts/status pane, for diagnostics.
func status_text() -> String:
	return _status.text if _status != null else ""


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

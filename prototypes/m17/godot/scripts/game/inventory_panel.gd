class_name InventoryPanel
extends Control

## Full inventory interface.
##
## Shows the nine slots at a readable size, lets stacks be reordered (click to
## pick a stack up and place it again, or drag a slot onto another), and explains
## the selected item: what it is, how much of it fits in a stack, its tool or food
## values, and which recipes consume or produce it.
##
## Presentation and intent only: every mutation goes through `Inventory`, and the
## recipe facts come from `Crafting`, so the interface can never invent state.

signal changed_stack(item_id: int)

const PANEL_WIDTH := 780
const GRID_HEIGHT := 120
const DETAIL_WIDTH := 300
const CARRY_SIZE := 52

var inventory: Inventory
var library: TextureLibrary

var _slots: Array[InventorySlot] = []
var _carry_slot: InventorySlot
var _carry_label: Label
var _detail: Label
var _hint: Label
var _carried: Dictionary = {}
var _focus_index := 0


func setup(player_inventory: Inventory, texture_library: TextureLibrary = null) -> void:
	inventory = player_inventory
	library = texture_library
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
	style.bg_color = Color(0.05, 0.07, 0.1, 0.96)
	style.border_color = Color(1, 1, 1, 0.28)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	box.add_theme_stylebox_override("panel", style)
	center.add_child(box)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	box.add_child(margin)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	margin.add_child(columns)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)

	var title := Label.new()
	title.text = "INVENTORY"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	left.add_child(title)

	var grid := GridContainer.new()
	grid.name = "Slots"
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	left.add_child(grid)
	for index in Inventory.HOTBAR_SIZE:
		var slot := InventorySlot.new()
		slot.configure(index, inventory, library)
		slot.clicked.connect(_on_slot_clicked)
		slot.stack_moved.connect(_on_stack_moved)
		grid.add_child(slot)
		_slots.append(slot)

	var carry_row := HBoxContainer.new()
	carry_row.add_theme_constant_override("separation", 12)
	left.add_child(carry_row)
	var carry_title := Label.new()
	carry_title.text = "CARRYING"
	carry_title.add_theme_font_size_override("font_size", 13)
	carry_title.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 0.9))
	carry_row.add_child(carry_title)
	_carry_slot = InventorySlot.new()
	_carry_slot.configure(-1, inventory, library)
	_carry_slot.custom_minimum_size = Vector2(CARRY_SIZE, CARRY_SIZE)
	carry_row.add_child(_carry_slot)
	_carry_label = Label.new()
	_carry_label.add_theme_font_size_override("font_size", 14)
	_carry_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	carry_row.add_child(_carry_label)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(0.68, 0.78, 0.88, 0.85))
	left.add_child(_hint)

	var detail_box := PanelContainer.new()
	detail_box.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	var detail_style := StyleBoxFlat.new()
	detail_style.bg_color = Color(0.07, 0.09, 0.13, 0.9)
	detail_style.set_corner_radius_all(5)
	detail_style.set_content_margin_all(10)
	detail_box.add_theme_stylebox_override("panel", detail_style)
	columns.add_child(detail_box)
	_detail = Label.new()
	_detail.custom_minimum_size = Vector2(DETAIL_WIDTH - 20, 0)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_theme_font_size_override("font_size", 13)
	_detail.add_theme_color_override("font_color", Color(0.88, 0.93, 0.99))
	detail_box.add_child(_detail)


# --- interaction ---------------------------------------------------------

func _on_slot_clicked(index: int) -> void:
	if _carried.is_empty():
		pick_up(index)
	else:
		put_down(index)


func _on_stack_moved(from: int, to: int) -> void:
	if inventory != null and inventory.move_slot(from, to):
		_focus_index = to
		changed_stack.emit(inventory.slots[to])
	_refresh()


## Picks the whole stack out of a slot (and makes it the carried one).
func pick_up(index: int) -> bool:
	if inventory == null or _carried.size() > 0:
		return false
	var stack := inventory.take_stack(index)
	if stack.is_empty():
		return false
	_carried = stack
	_focus_index = index
	changed_stack.emit(int(stack["item"]))
	_refresh()
	return true


## Puts the carried stack into a slot.  Whatever does not fit stays carried.
func put_down(index: int) -> bool:
	if inventory == null or _carried.is_empty():
		return false
	var leftover: Dictionary = inventory.put_stack(index, _carried)
	_carried = leftover
	_focus_index = index
	if not _carried.is_empty():
		changed_stack.emit(int(_carried["item"]))
	_refresh()
	return true


## Swaps two slots (also the model path used by the drag & drop drop handler).
func swap(a: int, b: int) -> bool:
	if inventory == null or not inventory.swap_slots(a, b):
		return false
	_refresh()
	return true


func carried() -> Dictionary:
	return _carried.duplicate()


func slot_count() -> int:
	return _slots.size()


## Text of the item facts pane, for diagnostics.
func detail_text() -> String:
	return _detail.text


## Selects a slot for the item facts pane (also what a left-click on a slot does).
func focus_slot(index: int) -> void:
	_focus_index = clampi(index, 0, Inventory.HOTBAR_SIZE - 1)
	if inventory != null:
		inventory.select(_focus_index)
	_refresh()


# --- state ---------------------------------------------------------------

func _refresh() -> void:
	if inventory == null:
		return
	var selected := inventory.selected
	for slot: InventorySlot in _slots:
		slot.selected = slot.index == selected
		slot.refresh()
	_carry_slot.index = -1
	_carry_slot.visible = false
	if _carried.is_empty():
		_carry_slot.override_stack = {}
		_carry_label.text = "nothing — click a slot to pick a stack up"
	else:
		_carry_label.text = "%d %s" % [int(_carried["count"]), ItemDB.name_of(int(_carried["item"]))]
		_carry_slot.visible = true
		_carry_slot.override_stack = _carried
		_carry_slot.refresh()
	_hint.text = "Click a stack to carry it, click a slot to drop it · drag a slot onto another to reorder · " \
		+ "1-9 or click selects the hotbar slot · I or Esc closes"
	_update_detail()


## Draws the carried stack in its own small slot (it has left the inventory, so the
## slot control reads it from `override_stack`).
func _draw_carry() -> void:
	_carry_slot.override_stack = _carried
	_carry_slot.refresh()


func _update_detail() -> void:
	var item_id := inventory.slots[_focus_index] if _focus_index >= 0 and _focus_index < Inventory.HOTBAR_SIZE \
		else BlockDB.AIR
	if item_id == BlockDB.AIR and not _carried.is_empty():
		item_id = int(_carried["item"])
	if item_id == BlockDB.AIR:
		_detail.text = "No item selected.\n\nClick or drag a stack, or press 1-9."
		return
	var lines: Array = []
	lines.append(ItemDB.name_of(item_id))
	lines.append(_kind_text(item_id))
	lines.append("")
	if ItemDB.is_block(item_id):
		var block_id := item_id
		lines.append("Block: %s" % BlockDB.name_of(block_id))
		lines.append("Hardness: %.2f  ·  %s" % [float(BlockDB.hardness[block_id]),
			"solid" if BlockDB.is_solid(block_id) else "passable"])
		var drop := ItemDB.drop_for_block(block_id)
		if drop != BlockDB.NO_DROP:
			lines.append("Drops: %s" % ItemDB.name_of(drop))
		var required := ItemDB.required_tool(block_id)
		if required != ItemDB.Tool.NONE:
			lines.append("Needs a %s (tier %s)" % [ItemDB.tool_name(required),
				ItemDB.tier_name(ItemDB.required_tier(block_id))])
	var maximum_stack := ItemDB.max_stack(item_id)
	lines.append("Stack: %d" % maximum_stack)
	var held := inventory.count_of(item_id)
	lines.append("Held: %d" % held)
	if ItemDB.is_tool_item(item_id):
		lines.append("")
		lines.append("Tool tier: %s" % ItemDB.tier_name(ItemDB.tier(item_id)))
		lines.append("Mining speed: %.1fx" % ItemDB.mining_speed(item_id))
		lines.append("Attack: %d" % int(round(ItemDB.attack_damage(item_id))))
		var wear := inventory.durability_of(_focus_index)
		var maximum_wear := ItemDB.max_durability(item_id)
		lines.append("Durability: %d / %d" % [wear, maximum_wear])
		if maximum_wear > 0:
			lines.append("Blocks left: about %d" % wear)
	if ItemDB.is_food(item_id):
		lines.append("")
		lines.append("Food: +%d hunger" % int(ItemDB.food_value(item_id)))
		if ItemDB.heal_value(item_id) > 0.0:
			lines.append("Also heals %d" % int(ItemDB.heal_value(item_id)))
	var made_by := _recipe_making(item_id)
	if not made_by.is_empty():
		lines.append("")
		lines.append("Made by: %s" % Crafting.label(made_by))
	var used_in := _recipes_using(item_id)
	if not used_in.is_empty():
		lines.append("")
		lines.append("Used in %d recipe%s:" % [used_in.size(), "" if used_in.size() == 1 else "s"])
		for recipe: Dictionary in used_in:
			lines.append("  · %s" % Crafting.label(recipe))
	_detail.text = "\n".join(lines)


func _kind_text(item_id: int) -> String:
	if ItemDB.is_tool_item(item_id):
		return "%s tool (%s)" % [ItemDB.tier_name(ItemDB.tier(item_id)), ItemDB.tool_name(ItemDB.tool_class(item_id))]
	if ItemDB.is_food(item_id):
		return "Food"
	if ItemDB.is_block(item_id):
		return "Block"
	if item_id == BlockDB.WATER:
		return "Liquid"
	return "Material"


func _recipe_making(item_id: int) -> Dictionary:
	for recipe: Dictionary in Crafting.recipes():
		if int(recipe["output"]) == item_id:
			return recipe
	return {}


func _recipes_using(item_id: int) -> Array:
	var found: Array = []
	for recipe: Dictionary in Crafting.recipes():
		if Crafting.ingredients(recipe).has(item_id) or Crafting.fuel(recipe).has(item_id):
			found.append(recipe)
	return found


# --- visibility ----------------------------------------------------------

func open() -> void:
	_refresh()
	visible = true


func close() -> void:
	# A carried stack must never be lost: closing with one in hand puts it back.
	if not _carried.is_empty() and inventory != null:
		var leftover: Dictionary = inventory.put_stack(_focus_index, _carried)
		var index := 0
		while not leftover.is_empty() and index < Inventory.HOTBAR_SIZE:
			leftover = inventory.put_stack(index, leftover)
			index += 1
		_carried = {}
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func is_open() -> bool:
	return visible

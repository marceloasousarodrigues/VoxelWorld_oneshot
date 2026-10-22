extends RefCounted

## M20 stabilization regressions: furnace recipe availability, inventory
## ownership conservation, and the ground face under an open station model.
##
## These tests are deliberately scenario-shaped: they use the real catalogue,
## the real station grid, the real interfaces and the real chunk mesher.

const StationModel = preload("res://scripts/core/station.gd")


func name() -> String:
	return "M20 stabilization"


func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


# =========================================================================
# Furnace recipe: 8 cobblestone, table crafting and the 3x3 grid
# =========================================================================

func _test_furnace_recipe(h: TestHarness) -> void:
	h.section("furnace recipe availability")
	var furnace := Crafting.recipe("furnace")
	h.eq(Crafting.ingredients(furnace), {BlockDB.COBBLESTONE: 8},
		"the furnace recipe is eight cobblestone")
	h.eq(int(furnace["output"]), BlockDB.FURNACE, "the furnace recipe outputs one furnace")
	h.eq(int(furnace["output_count"]), 1, "the furnace recipe outputs exactly one")
	h.eq(Crafting.station_of(furnace), Crafting.STATION_TABLE,
		"the furnace requires a crafting table")

	var inventory := Inventory.new()
	inventory.add(BlockDB.COBBLESTONE, 8)
	h.check(Crafting.can_craft(inventory, furnace, Crafting.STATION_TABLE),
		"eight cobblestone are craftable at a table in the model")
	h.check(Crafting.available_recipes(inventory, Crafting.STATION_TABLE).any(
		func(entry: Dictionary) -> bool: return str(entry.get("id", "")) == "furnace"),
		"recipe discovery includes the furnace at a table")
	h.check(not Crafting.can_craft(inventory, furnace, Crafting.STATION_HAND),
		"the furnace is not craftable by hand")

	# The catalogue must expose and perform the craft when the station is
	# available; this was the reported "eight cobblestone but not craftable".
	var panel := CraftingPanel.new()
	panel.setup(inventory, null)
	panel.set_station(Crafting.STATION_TABLE)
	panel.open()
	h.check(panel.row_enabled("furnace"), "the catalogue enables the furnace at a table")
	h.check(panel.press_craft("furnace"), "the catalogue's Craft button performs the furnace craft")
	h.eq(inventory.count_of(BlockDB.COBBLESTONE), 0, "exactly eight cobblestone were consumed")
	h.eq(inventory.count_of(BlockDB.FURNACE), 1, "exactly one furnace was created")
	h.eq(inventory.used_slots(), 1, "the craft left one furnace stack and nothing else")
	panel.free()

	# Without a table the recipe is visible but not craftable.
	var hand_inventory := Inventory.new()
	hand_inventory.add(BlockDB.COBBLESTONE, 8)
	var hand_panel := CraftingPanel.new()
	hand_panel.setup(hand_inventory, null)
	hand_panel.set_station(Crafting.STATION_HAND)
	hand_panel.open()
	h.check(not hand_panel.row_enabled("furnace"),
		"the furnace stays disabled without a crafting table")
	h.check(hand_panel.row_status("furnace").to_lower().contains("table"),
		"the disabled row names the required table")
	h.check(not hand_panel.press_craft("furnace"), "a disabled furnace button does nothing")
	h.eq(hand_inventory.count_of(BlockDB.COBBLESTONE), 8,
		"a refused furnace craft consumes no cobblestone")
	hand_panel.free()

	# The real 3x3 grid must accept the same eight cobblestone whether they are
	# arranged across cells or left as one stack in a single cell.
	var table := StationModel.new(StationModel.TABLE)
	for grid_index in [0, 1, 2, 3, 5, 6, 7, 8]:
		table.inventory.insert(grid_index, {"item": BlockDB.COBBLESTONE, "count": 1})
	h.eq(str(table.matched_recipe().get("id", "")), "furnace",
		"eight cobblestone across eight grid cells match the furnace")
	var spread_result: Dictionary = table.craft_grid()
	h.check(bool(spread_result["ok"]), "the spread grid crafts a furnace")
	h.eq(int(spread_result["output"]), BlockDB.FURNACE, "the spread grid output is a furnace")
	h.eq(table.inventory.total_of(BlockDB.COBBLESTONE), 0,
		"the spread grid consumed exactly eight cobblestone")

	var stacked := StationModel.new(StationModel.TABLE)
	stacked.inventory.insert(0, {"item": BlockDB.COBBLESTONE, "count": 8})
	h.eq(str(stacked.matched_recipe().get("id", "")), "furnace",
		"eight cobblestone stacked in one cell match the shapeless furnace recipe")
	var stack_result: Dictionary = stacked.craft_grid()
	h.check(bool(stack_result["ok"]), "the stacked grid crafts a furnace")
	h.eq(int(stack_result["output"]), BlockDB.FURNACE, "the stacked grid output is a furnace")
	h.eq(stacked.inventory.total_of(BlockDB.COBBLESTONE), 0,
		"the stacked grid consumed exactly eight cobblestone")
	h.eq(stacked.inventory.count_at(StationModel.TABLE_OUTPUT_SLOT), 1,
		"the stacked grid produced exactly one furnace")


# =========================================================================
# Item ownership conservation
# =========================================================================

## Total owned items, including the temporary cursor stack, so a UI operation
## that copies a stack instead of transferring it is visible immediately.
func _owned(inventory: Inventory, carried: Dictionary = {}, station: Station = null) -> Dictionary:
	var totals := {}
	for index in inventory.size():
		if inventory.is_empty(index):
			continue
		var item_id := inventory.item_at(index)
		totals[item_id] = int(totals.get(item_id, 0)) + inventory.count_at(index)
	if station != null:
		for index in station.inventory.size():
			if station.inventory.is_empty(index):
				continue
			var item_id := station.inventory.item_at(index)
			totals[item_id] = int(totals.get(item_id, 0)) + station.inventory.count_at(index)
	if not carried.is_empty():
		var item_id := int(carried.get("item", BlockDB.AIR))
		totals[item_id] = int(totals.get(item_id, 0)) + int(carried.get("count", 0))
	return totals


func _test_inventory_panel_conservation(h: TestHarness) -> void:
	h.section("inventory panel conservation")
	var inventory := Inventory.new()
	inventory.give_starter_kit()
	inventory.add(ItemDB.IRON_LUMP, 10)
	inventory.add(BlockDB.STONE, 50)
	var panel := InventoryPanel.new()
	panel.setup(inventory, null)
	_root().add_child(panel)
	panel.open()

	var before := _owned(inventory, panel.carried())
	_check_same(h, before, _owned(inventory, panel.carried()), "panel opening")

	# Whole-stack transfer to a storage slot.
	inventory.clear_slot(20)
	panel.click_slot(0)
	panel.click_slot(20)
	_check_same(h, before, _owned(inventory, panel.carried()), "pick up and place")

	# Split, place one, and return the cursor.
	inventory.clear_slot(21)
	panel.click_slot(9, MOUSE_BUTTON_RIGHT)
	_check_same(h, before, _owned(inventory, panel.carried()), "right-click split")
	panel.click_slot(21, MOUSE_BUTTON_RIGHT)
	_check_same(h, before, _owned(inventory, panel.carried()), "right-click place one")
	panel.click_slot(22)
	_check_same(h, before, _owned(inventory, panel.carried()), "place split remainder")

	# Quick move both ways.
	panel.click_slot(4, MOUSE_BUTTON_LEFT, true)
	_check_same(h, before, _owned(inventory, panel.carried()), "hotbar to storage quick move")
	panel.click_slot(9, MOUSE_BUTTON_LEFT, true)
	_check_same(h, before, _owned(inventory, panel.carried()), "storage to hotbar quick move")

	# A drag/swaps through the model handler.
	panel.swap(5, 23)
	_check_same(h, before, _owned(inventory, panel.carried()), "slot swap")

	# Repeated pick up / put down must never copy.
	for step in 12:
		var from := 0 if step % 2 == 0 else 10
		if inventory.is_empty(from):
			continue
		panel.pick_up(from)
		panel.put_down(24 if step % 2 == 0 else 11)
		_check_same(h, before, _owned(inventory, panel.carried()), "repeated transfer %d" % step)

	# Close with a cursor stack: ownership returns to the model.
	inventory.clear_slot(25)
	inventory.put_stack(25, {"item": ItemDB.IRON_LUMP, "count": 7})
	before = _owned(inventory, panel.carried())
	panel.pick_up(25)
	_check_same(h, before, _owned(inventory, panel.carried()), "cursor before close")
	var closed := panel.close()
	_check_same(h, before, _owned(inventory, panel.carried()), "cursor recovery on close")
	h.check(closed, "the cursor stack fits back into the inventory")
	panel.free()


func _test_station_panel_conservation(h: TestHarness) -> void:
	h.section("station panel conservation")
	var inventory := Inventory.new()
	inventory.give_starter_kit()
	inventory.add(BlockDB.COBBLESTONE, 12)
	inventory.add(BlockDB.PLANKS, 12)
	inventory.add(ItemDB.STICK, 8)
	var table := StationModel.new(StationModel.TABLE)
	table.inventory.insert(0, {"item": BlockDB.PLANKS, "count": 4})
	table.inventory.insert(4, {"item": ItemDB.STICK, "count": 2})
	var panel := StationPanel.new()
	panel.setup(inventory, null)
	_root().add_child(panel)
	panel.open_station(table)

	var before := _owned(inventory, panel.carried(), table)
	_check_same(h, before, _owned(inventory, panel.carried(), table), "station panel opening")

	# Player -> grid -> player without crafting.
	var plank_slot := inventory.slots.find(BlockDB.PLANKS)
	panel.click_slot("player", plank_slot)
	panel.click_slot("station", 8)
	_check_same(h, before, _owned(inventory, panel.carried(), table), "player to grid")
	panel.click_slot("station", 8)
	panel.click_slot("player", plank_slot)
	_check_same(h, before, _owned(inventory, panel.carried(), table), "grid back to player")

	# Shift-click into the grid spreads one per cell; moving all cells back must
	# conserve the stack exactly.
	var stick_slot := inventory.slots.find(ItemDB.STICK)
	panel.click_slot("player", stick_slot, MOUSE_BUTTON_LEFT, true)
	_check_same(h, before, _owned(inventory, panel.carried(), table), "shift-click into grid")
	var grid_sticks: Array[int] = []
	for index in StationModel.TABLE_GRID_SLOTS:
		if table.inventory.item_at(index) == ItemDB.STICK:
			grid_sticks.append(index)
	for index in grid_sticks:
		panel.move_between("station", index, "player", stick_slot)
	_check_same(h, before, _owned(inventory, panel.carried(), table), "dragging grid stacks back")

	# Shift-click from the station to the player is the operation that used to
	# duplicate the stack: it was added to the player and also put back in the
	# station.  Assert both sides explicitly, not just the total.
	table.inventory.insert(6, {"item": ItemDB.IRON_LUMP, "count": 5})
	before = _owned(inventory, panel.carried(), table)
	var iron_before := inventory.count_of(ItemDB.IRON_LUMP)
	h.check(panel.quick_move("station", 6), "shift-click moves a stack from the station")
	h.check(inventory.count_of(ItemDB.IRON_LUMP) == iron_before + 5,
		"the player received exactly five iron lumps")
	h.check(table.inventory.total_of(ItemDB.IRON_LUMP) == 0,
		"the station no longer holds the shifted stack")
	_check_same(h, before, _owned(inventory, panel.carried(), table),
		"station-to-player shift-click")

	# Right-clicking one item into an occupied incompatible slot must refuse
	# before touching the model; it previously swapped and dropped the target.
	inventory.clear_slot(30)
	inventory.put_stack(30, {"item": BlockDB.SAND, "count": 10, "durability": 0})
	table.inventory.insert(7, {"item": ItemDB.IRON_LUMP, "count": 3})
	before = _owned(inventory, panel.carried(), table)
	panel.pick_up("station", 7)
	h.check(not panel.put_one("player", 30),
		"right-clicking one iron lump onto sand is refused")
	h.eq(inventory.item_at(30), BlockDB.SAND, "the incompatible target keeps its item")
	h.eq(inventory.count_at(30), 10, "the incompatible target keeps its count")
	h.eq(int(panel.carried().get("count", 0)), 3, "the cursor keeps the whole iron stack")
	_check_same(h, before, _owned(inventory, panel.carried(), table),
		"refused right-click placement")
	# Return the cursor stack before the next close test.
	panel.put_down("station", 7)

	# Cursor recovery from a station slot back into the station.
	table.inventory.insert(5, {"item": ItemDB.IRON_LUMP, "count": 3})
	before = _owned(inventory, panel.carried(), table)
	panel.pick_up("station", 5)
	_check_same(h, before, _owned(inventory, panel.carried(), table), "station stack on cursor")
	var closed := panel.close()
	_check_same(h, before, _owned(inventory, panel.carried(), table), "station cursor recovery")
	h.check(closed, "the station cursor stack returns to its origin")
	panel.free()


## The exact "take the result, close, reopen, take again" sequence.  The second
## take must not create a second output out of the same ingredients.
func _test_crafting_result_conservation(h: TestHarness) -> void:
	h.section("crafting result conservation")
	var inventory := Inventory.new()
	inventory.add(BlockDB.PLANKS, 4)
	var table := StationModel.new(StationModel.TABLE)
	for index in [0, 1, 3, 4]:
		table.inventory.insert(index, {"item": BlockDB.PLANKS, "count": 1})
	var panel := StationPanel.new()
	panel.setup(inventory, null)
	_root().add_child(panel)
	panel.open_station(table)

	h.check(panel.take_output(), "the first crafted result is taken")
	h.eq(int(panel.carried().get("count", 0)), 1, "the first result is one crafting table")
	var player_slot := inventory.slots.find(BlockDB.AIR)
	panel.put_down("player", player_slot)
	h.eq(inventory.count_of(BlockDB.CRAFTING_TABLE), 1, "the first result entered the inventory")
	h.check(panel.close(), "the table interface closes")
	panel.open_station(table)
	h.check(table.inventory.is_empty(StationModel.TABLE_OUTPUT_SLOT),
		"the result slot is empty after the first take")
	h.check(not panel.take_output(), "a second take without ingredients produces nothing")
	h.eq(inventory.count_of(BlockDB.CRAFTING_TABLE), 1,
		"the second take did not duplicate the crafting table")
	h.eq(table.inventory.total_items(), 0, "the grid is empty after the first craft")
	panel.free()


func _check_same(h: TestHarness, before: Dictionary, after: Dictionary, label: String) -> void:
	h.eq(after, before, "%s conserves every item" % label)


# =========================================================================
# Cursor flush before persistence
# =========================================================================

## A save or load must not leave a temporary cursor stack as a second copy, and
## must not drop it either.  Both panels must be able to return the cursor to
## their models without closing, and refuse to when there is genuinely no room.
func _test_cursor_flush(h: TestHarness) -> void:
	h.section("cursor flush before persistence")
	var inventory := Inventory.new()
	inventory.give_starter_kit()
	inventory.add(ItemDB.IRON_LUMP, 10)
	var panel := InventoryPanel.new()
	panel.setup(inventory, null)
	_root().add_child(panel)
	panel.open()
	var before := _owned(inventory, panel.carried())
	panel.pick_up(inventory.slots.find(ItemDB.IRON_LUMP))
	h.check(not panel.carried().is_empty(), "the stack is on the cursor")
	h.check(panel.flush_cursor(), "flush_cursor succeeds with room to spare")
	h.check(panel.carried().is_empty(), "flush_cursor empties the cursor")
	h.check(panel.is_open(), "flush_cursor keeps the panel open")
	_check_same(h, before, _owned(inventory, panel.carried()), "flush_cursor conserves the items")
	panel.free()

	# A genuinely full inventory refuses to flush: nothing may be destroyed.
	var full := Inventory.new()
	for index in Inventory.SIZE:
		full.put_stack(index, {"item": BlockDB.STONE, "count": 64})
	full.clear_slot(20)
	full.put_stack(20, {"item": BlockDB.GRAVEL, "count": 5})
	var full_panel := InventoryPanel.new()
	full_panel.setup(full, null)
	_root().add_child(full_panel)
	full_panel.open()
	h.check(full_panel.pick_up(20), "the gravel stack is picked up")
	full.put_stack(20, {"item": BlockDB.DIRT, "count": 64})
	h.check(not full_panel.flush_cursor(), "a full inventory refuses the flush")
	h.eq(int(full_panel.carried().get("count", 0)), 5, "the refused cursor stack is preserved")
	h.eq(full.count_of(BlockDB.GRAVEL), 0, "the refused gravel is not destroyed")
	full_panel.free()

	# The station interface keeps the same contract.
	var station_inventory := Inventory.new()
	station_inventory.give_starter_kit()
	var table := StationModel.new(StationModel.TABLE)
	table.inventory.insert(0, {"item": BlockDB.PLANKS, "count": 4})
	var station_panel := StationPanel.new()
	station_panel.setup(station_inventory, null)
	_root().add_child(station_panel)
	station_panel.open_station(table)
	var station_before := _owned(station_inventory, station_panel.carried(), table)
	station_panel.pick_up("station", 0)
	h.check(not station_panel.carried().is_empty(), "the station stack is on the cursor")
	h.check(station_panel.flush_cursor(), "the station flush succeeds")
	h.check(station_panel.carried().is_empty(), "the station cursor is emptied")
	_check_same(h, station_before, _owned(station_inventory, station_panel.carried(), table),
		"the station flush conserves the items")
	station_panel.free()


# =========================================================================
# Ground face under the open station model
# =========================================================================

func _make_chunk(world: VoxelWorld, coord: Vector3i) -> ChunkData:
	var chunk := ChunkData.new(coord)
	chunk.generated = true
	world.adopt_chunk(chunk)
	return chunk


func _test_station_ground_face(h: TestHarness) -> void:
	h.section("station ground face")
	var library := TextureLibrary.new()
	library.load_all()
	var mesher := ChunkMesher.new(library, VoxelMaterials.new(library))
	var world := VoxelWorld.new(17017)
	var chunk := _make_chunk(world, Vector3i.ZERO)
	var ground := Vector3i(4, 8, 4)
	var station := Vector3i(4, 9, 4)
	chunk.blocks[ChunkData.cell_index(ground.x, ground.y, ground.z)] = BlockDB.STONE
	chunk.blocks[ChunkData.cell_index(station.x, station.y, station.z)] = BlockDB.CRAFTING_TABLE
	# Terrain beside and above the open model must stay visible too.
	chunk.blocks[ChunkData.cell_index(5, 9, 4)] = BlockDB.STONE
	chunk.blocks[ChunkData.cell_index(4, 10, 4)] = BlockDB.STONE
	var result := mesher.build(chunk, world)
	var arrays: Array = _opaque_arrays(result)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var ground_top := false
	for index in vertices.size():
		var vertex := vertices[index]
		if not is_equal_approx(vertex.y, 9.0):
			continue
		if vertex.x < 4.0 or vertex.x > 5.0 or vertex.z < 4.0 or vertex.z > 5.0:
			continue
		if normals[index].y > 0.9:
			ground_top = true
			break
	h.check(ground_top,
		"the stone top face is emitted under the open-legged crafting table")
	h.check(_has_face(vertices, normals, 0, 5.0, 0, -1.0),
		"the stone face beside the table is emitted")
	h.check(_has_face(vertices, normals, 1, 10.0, 1, -1.0),
		"the stone face above the table is emitted")
	h.check(not BlockDB.hides_neighbour_face(BlockDB.STONE, BlockDB.CRAFTING_TABLE),
		"a station does not cull the ground face below it")
	h.check(not BlockDB.hides_neighbour_face(BlockDB.STONE, BlockDB.FURNACE),
		"a furnace also leaves neighbouring faces visible")
	h.check(BlockDB.is_solid(BlockDB.CRAFTING_TABLE),
		"the station remains a solid logical/collision block")

	# Removing the station and rebuilding leaves the ground face intact.
	world.set_block(station, BlockDB.AIR)
	chunk.mark_dirty()
	var removed_result := mesher.build(chunk, world)
	var removed_arrays: Array = _opaque_arrays(removed_result)
	var removed_vertices: PackedVector3Array = removed_arrays[Mesh.ARRAY_VERTEX]
	var removed_normals: PackedVector3Array = removed_arrays[Mesh.ARRAY_NORMAL]
	var still_there := false
	for index in removed_vertices.size():
		var vertex := removed_vertices[index]
		if is_equal_approx(vertex.y, 9.0) and vertex.x >= 4.0 and vertex.x <= 5.0 \
				and vertex.z >= 4.0 and vertex.z <= 5.0 and removed_normals[index].y > 0.9:
			still_there = true
			break
	h.check(still_there, "the ground top face remains after the station is removed")


func _opaque_arrays(result: Dictionary) -> Array:
	var mesh: ArrayMesh = result["mesh"]
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 0:
			return arrays
	return []


## True when the mesh has a vertex on the given plane with a normal pointing the
## required way: a compact "is this face emitted" check.
func _has_face(vertices: PackedVector3Array, normals: PackedVector3Array,
		plane_axis: int, plane_value: float, normal_axis: int, normal_dir: float) -> bool:
	for index in vertices.size():
		if absf(vertices[index][plane_axis] - plane_value) > 0.001:
			continue
		if normals[index][normal_axis] * normal_dir > 0.9:
			return true
	return false


func _test_random_conservation(h: TestHarness) -> void:
	h.section("randomized conservation")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261019

	var inventory := Inventory.new()
	inventory.give_starter_kit()
	for item_id in [ItemDB.IRON_LUMP, ItemDB.COAL, BlockDB.STONE, BlockDB.COBBLESTONE,
			ItemDB.STICK, BlockDB.OAK_LOG]:
		inventory.add(item_id, 24)
	var panel := InventoryPanel.new()
	panel.setup(inventory, null)
	_root().add_child(panel)
	panel.open()
	var baseline := _owned(inventory, panel.carried())
	var failures := 0
	for step in 800:
		var slot := rng.randi_range(0, Inventory.SIZE - 1)
		if panel.carried().is_empty():
			match rng.randi_range(0, 3):
				0:
					if not inventory.is_empty(slot):
						panel.pick_up(slot)
				1:
					panel.split_half(slot)
				2:
					panel.quick_move(slot)
				3:
					panel.swap(slot, rng.randi_range(0, Inventory.SIZE - 1))
		else:
			match rng.randi_range(0, 3):
				0:
					panel.put_down(slot)
				1:
					panel.put_one(slot)
				2:
					panel.put_down(rng.randi_range(0, Inventory.SIZE - 1))
				3:
					panel.close()
					if not panel.is_open():
						panel.open()
		if _owned(inventory, panel.carried()) != baseline:
			failures += 1
			break
	h.eq(failures, 0, "800 random inventory-panel operations preserve ownership")
	if panel.is_open():
		panel.close()
	panel.free()

	var station_inventory := Inventory.new()
	station_inventory.give_starter_kit()
	for item_id in [BlockDB.PLANKS, BlockDB.COBBLESTONE, ItemDB.STICK, ItemDB.IRON_LUMP]:
		station_inventory.add(item_id, 16)
	var table := StationModel.new(StationModel.TABLE)
	table.inventory.insert(0, {"item": BlockDB.PLANKS, "count": 12})
	table.inventory.insert(4, {"item": ItemDB.STICK, "count": 8})
	var station_panel := StationPanel.new()
	station_panel.setup(station_inventory, null)
	_root().add_child(station_panel)
	station_panel.open_station(table)
	var station_baseline := _owned(station_inventory, station_panel.carried(), table)
	var station_failures := 0
	for step in 600:
		var side := "player" if rng.randf() < 0.5 else "station"
		var index := rng.randi_range(0, Inventory.SIZE - 1) if side == "player" \
			else rng.randi_range(0, StationModel.TABLE_GRID_SLOTS - 1)
		var op := ""
		var before_step := _owned(station_inventory, station_panel.carried(), table)
		if station_panel.carried().is_empty():
			match rng.randi_range(0, 2):
				0:
					op = "pick_up"
					station_panel.pick_up(side, index)
				1:
					op = "quick_move"
					station_panel.quick_move(side, index)
				2:
					op = "pick_up_half"
					station_panel.pick_up_half(side, index)
		else:
			match rng.randi_range(0, 2):
				0:
					op = "put_down"
					station_panel.put_down(side, index)
				1:
					op = "put_one"
					station_panel.put_one(side, index)
				2:
					op = "close_reopen"
					station_panel.close()
					if not station_panel.is_open():
						station_panel.open_station(table)
		var after_step := _owned(station_inventory, station_panel.carried(), table)
		if after_step != station_baseline:
			station_failures += 1
			print("M20_CONS_DIAG step=%d op=%s side=%s index=%d before=%s after=%s baseline=%s" % [
				step, op, side, index, str(before_step), str(after_step), str(station_baseline)])
			break
	h.eq(station_failures, 0, "600 random station transfers preserve ownership")
	if station_panel.is_open():
		station_panel.close()
	station_panel.free()


# =========================================================================

func run(h: TestHarness) -> void:
	_test_furnace_recipe(h)
	_test_station_ground_face(h)
	_test_inventory_panel_conservation(h)
	_test_station_panel_conservation(h)
	_test_crafting_result_conservation(h)
	_test_cursor_flush(h)
	_test_random_conservation(h)
	h.finish()

extends RefCounted

## Interactive stations (M19): the reusable station inventory, the smelting rules,
## the crafting table's grid crafting, the furnace's timed smelting and the
## registry that binds a station to a world position.
##
## These are the model-level guarantees the interfaces and the game rely on:
## nothing may be duplicated or destroyed by a move, a craft or a smelt, and a
## station's state must belong to exactly one world cell.

const StationModel = preload("res://scripts/core/station.gd")
const RegistryModel = preload("res://scripts/core/station_registry.gd")


func name() -> String:
	return "stations"


# --- helpers --------------------------------------------------------------

func _grid_roles() -> Array[String]:
	var roles: Array[String] = []
	for index in 9:
		roles.append(StationInventory.ROLE_GRID)
	roles.append(StationInventory.ROLE_OUTPUT)
	return roles


func _furnace_roles() -> Array[String]:
	var roles: Array[String] = [StationInventory.ROLE_INPUT, StationInventory.ROLE_FUEL, StationInventory.ROLE_OUTPUT]
	return roles


func _table_world() -> VoxelWorld:
	return VoxelWorld.new(17017)


func _place(world: VoxelWorld, position: Vector3i, block_id: int) -> void:
	world.ensure_chunk(VoxelWorld.world_to_chunk(position))
	if world.get_block(position) != block_id:
		world.set_block(position, block_id)


# =========================================================================

func run(h: TestHarness) -> void:
	_test_station_inventory(h)
	_test_smelting_rules(h)
	_test_station_detection(h)
	_test_crafting_table(h)
	_test_furnace(h)
	_test_registry(h)
	h.finish()


# --- the reusable container ----------------------------------------------

func _test_station_inventory(h: TestHarness) -> void:
	h.section("station inventory")
	var inventory := StationInventory.new(_grid_roles())
	h.eq(inventory.size(), 10, "the container has one slot per role entry")
	h.eq(inventory.role_of(0), StationInventory.ROLE_GRID, "grid slots report their role")
	h.eq(inventory.role_of(9), StationInventory.ROLE_OUTPUT, "the last slot is the output")
	h.check(inventory.is_empty(0), "a fresh container is empty")
	h.eq(inventory.total_items(), 0, "a fresh container holds nothing")

	# Acceptance by role.
	h.check(inventory.accepts(0, BlockDB.PLANKS), "a grid slot accepts an ordinary item")
	h.check(not inventory.accepts(9, BlockDB.PLANKS), "the output slot refuses player items")
	var furnace := StationInventory.new(_furnace_roles())
	h.check(furnace.accepts(0, ItemDB.IRON_LUMP), "the input slot accepts a smeltable item")
	h.check(not furnace.accepts(0, BlockDB.IRON_ORE),
		"the input slot refuses raw iron ore (it must be mined into a lump first)")
	h.check(not furnace.accepts(0, BlockDB.PLANKS), "the input slot refuses a non-smeltable item")
	h.check(furnace.accepts(1, ItemDB.COAL), "the fuel slot accepts a fuel item")
	h.check(not furnace.accepts(1, BlockDB.STONE), "the fuel slot refuses a non-fuel item")
	h.check(not furnace.accepts(2, ItemDB.COAL), "the output slot refuses player items")
	h.check(not inventory.accepts(0, BlockDB.AIR), "an empty item id is never accepted")

	# Stacking, caps and leftovers.
	var leftover: Dictionary = inventory.insert(0, {"item": BlockDB.PLANKS, "count": 10})
	h.check(leftover.is_empty(), "a stack that fits is absorbed completely")
	h.eq(inventory.item_at(0), BlockDB.PLANKS, "the inserted item is readable")
	h.eq(inventory.count_at(0), 10, "the inserted count is exact")
	leftover = inventory.insert(0, {"item": BlockDB.PLANKS, "count": 100})
	h.eq(int(leftover.get("count", 0)), 100 - (ItemDB.max_stack(BlockDB.PLANKS) - 10), "an oversized insert returns the remainder")
	h.eq(inventory.count_at(0), ItemDB.max_stack(BlockDB.PLANKS), "the slot is capped at the stack size")

	# A different item cannot overwrite a slot.
	var before := inventory.to_dictionary()
	leftover = inventory.insert(0, {"item": BlockDB.STONE, "count": 1, "durability": 0})
	h.eq(leftover, {"item": BlockDB.STONE, "count": 1, "durability": 0}, "inserting a different item returns it untouched")
	h.eq(inventory.to_dictionary(), before, "a refused insert changes nothing")

	# Insertion into a restricted slot through the player path is refused.
	leftover = furnace.insert(1, {"item": BlockDB.DIRT, "count": 3})
	h.eq(int(leftover.get("count", 0)), 3, "a non-fuel is refused by the fuel slot")
	h.eq(furnace.total_items(), 0, "the refused insert left the container empty")

	# Taking and splitting.
	var whole: Dictionary = inventory.take(0, -1)
	h.eq(int(whole["count"]), ItemDB.max_stack(BlockDB.PLANKS), "taking the whole stack returns every item")
	h.check(inventory.is_empty(0), "the emptied slot reads as empty")
	leftover = inventory.insert(1, {"item": BlockDB.SAND, "count": 30})
	var part: Dictionary = inventory.take(1, 12)
	h.eq(int(part["count"]), 12, "a partial take returns exactly the requested count")
	h.eq(inventory.count_at(1), 18, "the rest stays in the slot")
	h.eq(inventory.take(1, 100)["count"] if not inventory.is_empty(1) else -1, 18, "taking more than is held takes what is there")

	# Remove by item id across slots.
	inventory.insert(2, {"item": ItemDB.STICK, "count": 5})
	inventory.insert(3, {"item": ItemDB.STICK, "count": 5})
	h.eq(inventory.remove_item(ItemDB.STICK, 7), 7, "remove_item takes the requested amount across slots")
	h.eq(inventory.total_of(ItemDB.STICK), 3, "exactly the removed amount is gone")
	h.eq(inventory.remove_item(ItemDB.STICK, 99), 3, "remove_item takes what is left when short")
	h.eq(inventory.total_of(ItemDB.STICK), 0, "the item is gone")

	# Move: a matching stack merges, a different item swaps.
	inventory.clear_all()
	inventory.insert(0, {"item": BlockDB.DIRT, "count": 20})
	inventory.insert(1, {"item": BlockDB.DIRT, "count": 5})
	h.check(inventory.move(0, 1), "a matching stack can be merged")
	h.eq(inventory.count_at(1), 25, "the target absorbed the moved items")
	h.eq(inventory.count_at(0), 0, "the source gave up everything it could")

	# Move refuses a target that will not accept the item (a fuel slot).
	var furnace2 := StationInventory.new(_furnace_roles())
	furnace2.insert(0, {"item": ItemDB.IRON_LUMP, "count": 2})
	var fuel_before := furnace2.to_dictionary()
	h.check(not furnace2.move(0, 1), "moving a non-fuel into the fuel slot is refused")
	h.eq(furnace2.to_dictionary(), fuel_before, "a refused move changes nothing")

	# deposit() fills matching stacks then empty accepting slots, and never the
	# output slot; it returns exactly the amount that did not fit.
	var depot := StationInventory.new(_furnace_roles())
	depot.insert(0, {"item": ItemDB.IRON_LUMP, "count": 2})
	h.eq(depot.deposit({"item": ItemDB.IRON_LUMP, "count": 5, "durability": 0}), 0,
		"deposit tops up a matching stack")
	h.eq(depot.total_of(ItemDB.IRON_LUMP), 7, "the deposit count is exact")
	h.eq(depot.deposit({"item": ItemDB.COAL, "count": 3, "durability": 0}), 0,
		"deposit opens an empty accepting slot")
	h.eq(depot.total_of(ItemDB.COAL), 3, "the fuel was deposited")
	h.eq(depot.deposit({"item": BlockDB.STONE, "count": 5, "durability": 0}), 5,
		"deposit refuses a slot that does not accept the item")
	h.eq(depot.total_of(BlockDB.STONE), 0, "a refused deposit adds nothing")
	h.eq(depot.total_of(ItemDB.COAL), 3, "a refused deposit cannot use the output slot")

	# Serialisation: exact round-trip, malformed payloads rejected atomically.
	var source := StationInventory.new(_furnace_roles())
	source.insert(0, {"item": ItemDB.IRON_LUMP, "count": 4})
	source.insert(1, {"item": ItemDB.COAL, "count": 2})
	source.insert(2, {"item": ItemDB.IRON_INGOT, "count": 3}, true)
	var payload: Dictionary = source.to_dictionary()
	var restored := StationInventory.new(_furnace_roles())
	h.check(restored.from_dictionary(payload), "a station container restores from its payload")
	h.eq(restored.to_dictionary(), payload, "the restored container is identical")
	h.check(not restored.from_dictionary({"slots": []}), "a wrong-sized payload is rejected")
	var broken := payload.duplicate(true)
	(broken["slots"][0] as Array)[1] = 9999
	var snapshot := restored.to_dictionary()
	h.check(not restored.from_dictionary(broken), "an unknown item id is rejected")
	h.eq(restored.to_dictionary(), snapshot, "a rejected payload leaves the container untouched")
	var wrong_role := payload.duplicate(true)
	(wrong_role["slots"][0] as Array)[0] = StationInventory.ROLE_GRID
	h.check(not restored.from_dictionary(wrong_role), "a payload whose roles do not match is rejected")
	# A saved output slot is allowed even though a player cannot drop into it.
	var output_payload := StationInventory.new(_grid_roles()).to_dictionary()
	(output_payload["slots"][9] as Array)[1] = BlockDB.PLANKS
	(output_payload["slots"][9] as Array)[2] = 2
	h.check(StationInventory.new(_grid_roles()).from_dictionary(output_payload), "a stored output slot is a legal payload")


# --- smelting data --------------------------------------------------------

func _test_smelting_rules(h: TestHarness) -> void:
	h.section("smelting rules")
	h.approx(Smelting.fuel_seconds(ItemDB.COAL), 48.0, 1e-6, "coal is a long-burning fuel")
	h.approx(Smelting.fuel_seconds(BlockDB.PLANKS), 12.0, 1e-6, "planks are a short fuel")
	h.approx(Smelting.fuel_seconds(ItemDB.STICK), 4.0, 1e-6, "sticks are a very short fuel")
	h.approx(Smelting.fuel_seconds(BlockDB.STONE), 0.0, 1e-6, "stone is not fuel")
	h.check(Smelting.is_fuel(ItemDB.COAL), "coal is fuel")
	h.check(not Smelting.is_fuel(ItemDB.IRON_LUMP), "iron lump is not fuel")
	for leaf_id: int in [BlockDB.OAK_LEAVES, BlockDB.PINE_LEAVES,
			BlockDB.BIRCH_LEAVES, BlockDB.BLOSSOM_LEAVES]:
		h.check(Smelting.is_fuel(leaf_id), "%s is fuel" % BlockDB.name_of(leaf_id))
		h.approx(Smelting.fuel_seconds(leaf_id), 2.0, 1e-6,
			"%s burns for two seconds" % BlockDB.name_of(leaf_id))
		h.less(Smelting.fuel_seconds(leaf_id), Smelting.fuel_seconds(ItemDB.STICK),
			"%s is weaker than a stick" % BlockDB.name_of(leaf_id))

	h.check(Smelting.is_smeltable(ItemDB.IRON_LUMP), "iron lump is smeltable")
	h.check(not Smelting.is_smeltable(BlockDB.PLANKS), "planks are not smeltable")
	h.eq(Smelting.output_for(ItemDB.IRON_LUMP), ItemDB.IRON_INGOT, "iron lump smelts to an ingot")
	h.eq(Smelting.output_for(BlockDB.SAND), BlockDB.GLASS, "sand smelts to glass")
	h.eq(Smelting.output_for(BlockDB.COBBLESTONE), BlockDB.STONE, "cobblestone smelts to stone")
	h.eq(Smelting.output_count_for(ItemDB.IRON_LUMP), 1, "one lump yields one ingot")
	h.check((Smelting.recipe_for(BlockDB.PLANKS) as Dictionary).is_empty(), "a non-input has no furnace recipe")
	h.approx(Smelting.cook_seconds(Smelting.recipe_for(ItemDB.IRON_LUMP)), 8.0, 1e-6, "the iron recipe declares its own cook time")
	h.approx(Smelting.cook_seconds(Smelting.recipe_for(BlockDB.SAND)), 6.0, 1e-6, "an ordinary recipe uses the default cook time")


# --- station detection ----------------------------------------------------

## A station you can open with E must also unlock its recipes in the catalogue.
## The reported M20 bug was a four-block menu radius against a six-block reach.
func _test_station_detection(h: TestHarness) -> void:
	h.section("station detection")
	var world := _table_world()
	var table_cell := Vector3i(15, 100, 4)
	_place(world, table_cell, BlockDB.CRAFTING_TABLE)
	var near := Vector3i(10, 100, 4)
	h.eq(Crafting.best_station(world, near, 3), Crafting.STATION_HAND,
		"a table outside the scan radius is not detected")
	h.eq(Crafting.best_station(world, near, 4), Crafting.STATION_HAND,
		"a table five blocks away is outside the old four-block menu radius")
	h.eq(Crafting.best_station(world, near, 6), Crafting.STATION_TABLE,
		"a table within interaction reach unlocks table recipes")
	var furnace_cell := Vector3i(12, 100, 4)
	_place(world, furnace_cell, BlockDB.FURNACE)
	h.eq(Crafting.best_station(world, near, 6), Crafting.STATION_FURNACE,
		"a furnace outranks a table because it can also smelt")


# --- crafting table -------------------------------------------------------

func _test_crafting_table(h: TestHarness) -> void:
	h.section("crafting table")
	var table := StationModel.new(StationModel.TABLE)
	h.eq(table.inventory.size(), 10, "a table has nine grid slots and a result slot")
	h.eq(table.label(), "Crafting Table", "the table names itself")
	h.check(not table.is_furnace(), "a table is not a furnace")
	h.check(StationModel.is_station_block(BlockDB.CRAFTING_TABLE), "the crafting table block is a station")
	h.check(StationModel.is_station_block(BlockDB.FURNACE), "the furnace block is a station")
	h.check(not StationModel.is_station_block(BlockDB.STONE), "a stone block is not a station")

	h.check(table.result_preview().is_empty(), "an empty grid matches nothing")
	var refused: Dictionary = table.craft_grid()
	h.check(not bool(refused["ok"]), "crafting an empty grid is refused")

	# Shapeless: four planks make a crafting table.
	for index in [0, 1, 3, 4]:
		table.inventory.insert(index, {"item": BlockDB.PLANKS, "count": 1})
	h.eq(str(table.matched_recipe().get("id", "")), "crafting_table", "four planks match the crafting-table recipe")
	var result: Dictionary = table.craft_grid()
	h.check(bool(result["ok"]), "the matched recipe crafts")
	h.eq(int(result["output"]), BlockDB.CRAFTING_TABLE, "the craft produced a crafting table")
	h.eq(table.inventory.total_of(BlockDB.PLANKS), 0, "all four planks were consumed")
	h.eq(table.inventory.count_at(StationModel.TABLE_OUTPUT_SLOT), 1, "the result sits in the result slot")

	# Shapeless matching is quantity-aware: four planks stacked in one cell are
	# the same recipe ingredients as four planks spread across cells.
	table.inventory.insert(0, {"item": BlockDB.PLANKS, "count": 4})
	h.eq(str(table.matched_recipe().get("id", "")), "crafting_table",
		"four planks stacked in one cell still match the shapeless recipe")
	var stacked_craft: Dictionary = table.craft_grid()
	h.check(bool(stacked_craft["ok"]), "the stacked shapeless grid crafts")
	h.eq(table.inventory.total_of(BlockDB.PLANKS), 0,
		"the stacked shapeless craft consumed all four planks")
	table.inventory.take(StationModel.TABLE_OUTPUT_SLOT, -1)

	# A full result slot refuses the next craft atomically.  A crafting table
	# stacks to 64, so the slot is filled to its cap first.
	table.inventory.take(StationModel.TABLE_OUTPUT_SLOT, -1)
	table.inventory.insert(StationModel.TABLE_OUTPUT_SLOT,
		{"item": BlockDB.CRAFTING_TABLE, "count": ItemDB.max_stack(BlockDB.CRAFTING_TABLE)}, true)
	for index in [0, 1, 3, 4]:
		table.inventory.insert(index, {"item": BlockDB.PLANKS, "count": 1})
	var snapshot := table.inventory.to_dictionary()
	var blocked: Dictionary = table.craft_grid()
	h.check(not bool(blocked["ok"]), "a full result slot refuses a craft")
	h.eq(table.inventory.to_dictionary(), snapshot, "a refused craft consumes nothing")

	# Taking the result lets the same ingredients craft again.
	table.inventory.take(StationModel.TABLE_OUTPUT_SLOT, -1)
	h.check(bool(table.craft_grid()["ok"]), "the table can craft again once the result is taken")
	h.eq(table.inventory.count_at(StationModel.TABLE_OUTPUT_SLOT), 1, "the second result is in the result slot")

	# Shaped: the pickaxe pattern.
	var shaped := StationModel.new(StationModel.TABLE)
	# Row 0: PPP; rows 1 and 2: a stick in the middle column.
	for index in [0, 1, 2]:
		shaped.inventory.insert(index, {"item": BlockDB.PLANKS, "count": 1})
	for index in [4, 7]:
		shaped.inventory.insert(index, {"item": ItemDB.STICK, "count": 1})
	h.eq(str(shaped.matched_recipe().get("id", "")), "wood_pickaxe", "the pickaxe pattern matches its recipe")
	h.check(bool(shaped.craft_grid()["ok"]), "the shaped recipe crafts")
	h.eq(shaped.inventory.item_at(StationModel.TABLE_OUTPUT_SLOT), ItemDB.WOOD_PICKAXE, "the crafted pickaxe is in the result slot")
	h.eq(shaped.inventory.total_of(BlockDB.PLANKS), 0, "the planks were consumed")
	h.eq(shaped.inventory.total_of(ItemDB.STICK), 0, "the sticks were consumed")

	# A recipe whose output count is greater than one fills the result slot with
	# the whole output (a log makes four planks).
	var logs := StationModel.new(StationModel.TABLE)
	logs.inventory.insert(4, {"item": BlockDB.OAK_LOG, "count": 1})
	h.eq(str(logs.matched_recipe().get("id", "")), "planks_oak", "one log in any cell matches the planks recipe")
	var planks_result: Dictionary = logs.craft_grid()
	h.check(bool(planks_result["ok"]), "a multi-output recipe crafts")
	h.eq(int(planks_result["count"]), 4, "the craft result reports all four outputs")
	h.eq(logs.inventory.count_at(StationModel.TABLE_OUTPUT_SLOT), 4,
		"the result slot holds all four planks")

	# A recipe that needs a furnace is not craftable on a table.
	var smelt := StationModel.new(StationModel.TABLE)
	smelt.inventory.insert(0, {"item": ItemDB.IRON_LUMP, "count": 1})
	h.check((smelt.matched_recipe() as Dictionary).is_empty(), "a smelting input does not match a table recipe")

	# Leftovers return to the player; a full player keeps them in the station.
	var leftovers := StationModel.new(StationModel.TABLE)
	leftovers.inventory.insert(0, {"item": BlockDB.PLANKS, "count": 3})
	leftovers.inventory.insert(2, {"item": ItemDB.STICK, "count": 1})
	var player := Inventory.new()
	h.eq(leftovers.return_crafting_items(player), 4, "the leftovers return to the player")
	h.eq(player.count_of(BlockDB.PLANKS) + player.count_of(ItemDB.STICK), 4, "the player received every leftover")
	h.eq(leftovers.inventory.total_items(), 0, "the grid is empty after the return")
	var full := Inventory.new()
	h.eq(full.add(BlockDB.STONE, ItemDB.max_stack(BlockDB.STONE) * Inventory.SIZE), 0,
		"the filler inventory is completely full")
	var keep := StationModel.new(StationModel.TABLE)
	keep.inventory.insert(0, {"item": BlockDB.PLANKS, "count": 3})
	h.eq(keep.return_crafting_items(full), 0, "a full player receives nothing")
	h.eq(keep.inventory.total_of(BlockDB.PLANKS), 3, "the items stay in the grid rather than being destroyed")


# --- furnace --------------------------------------------------------------

func _test_furnace(h: TestHarness) -> void:
	h.section("furnace")
	var basic := StationModel.new(StationModel.FURNACE)
	h.eq(basic.inventory.size(), 3, "a furnace has input, fuel and output slots")
	h.eq(basic.label(), "Furnace", "the furnace names itself")
	h.check(basic.is_furnace(), "the furnace reports itself as a furnace")

	# A fuel item with nothing to smelt is never burned.
	var no_input := StationModel.new(StationModel.FURNACE)
	no_input.inventory.insert(StationModel.FURNACE_FUEL_SLOT, {"item": ItemDB.COAL, "count": 1})
	h.check(not no_input.step(10.0), "a furnace with no input does nothing")
	h.eq(no_input.inventory.count_at(StationModel.FURNACE_FUEL_SLOT), 1, "fuel is not consumed without an input")
	h.approx(no_input.burn_remaining, 0.0, 1e-6, "no fuel was lit")

	# An input with no fuel does not cook.
	var no_fuel := StationModel.new(StationModel.FURNACE)
	no_fuel.inventory.insert(StationModel.FURNACE_INPUT_SLOT, {"item": ItemDB.IRON_LUMP, "count": 1})
	h.check(not no_fuel.step(10.0), "a furnace with no fuel does nothing")
	h.eq(no_fuel.inventory.count_at(StationModel.FURNACE_INPUT_SLOT), 1, "the input is not consumed without fuel")

	# With both, the fuel lights and one cook completes after its cook time.
	var furnace := StationModel.new(StationModel.FURNACE)
	furnace.inventory.insert(StationModel.FURNACE_INPUT_SLOT, {"item": ItemDB.IRON_LUMP, "count": 1})
	furnace.inventory.insert(StationModel.FURNACE_FUEL_SLOT, {"item": ItemDB.COAL, "count": 1})
	h.check(furnace.step(0.1), "lighting the fuel reports a change")
	h.greater(furnace.burn_remaining, 0.0, "the fuel is burning")
	h.check(furnace.is_active(), "the furnace is active while it burns")
	h.eq(furnace.inventory.count_at(StationModel.FURNACE_FUEL_SLOT), 0, "one coal was consumed")
	h.check(furnace.cook_ratio() >= 0.0 and furnace.cook_ratio() < 1.0, "the cook has started but is not finished")
	var seconds := Smelting.cook_seconds(Smelting.recipe_for(ItemDB.IRON_LUMP))
	furnace.step(seconds + 0.001)
	h.eq(furnace.inventory.count_at(StationModel.FURNACE_OUTPUT_SLOT), 1, "the output appeared after the cook time")
	h.eq(furnace.inventory.item_at(StationModel.FURNACE_OUTPUT_SLOT), ItemDB.IRON_INGOT, "the output is an iron ingot")
	h.eq(furnace.inventory.count_at(StationModel.FURNACE_INPUT_SLOT), 0, "the input was consumed")

	# One coal smelts exactly eight items, and not a ninth.
	var batch := StationModel.new(StationModel.FURNACE)
	batch.inventory.insert(StationModel.FURNACE_INPUT_SLOT, {"item": BlockDB.SAND, "count": 9})
	batch.inventory.insert(StationModel.FURNACE_FUEL_SLOT, {"item": ItemDB.COAL, "count": 1})
	for step in 130:
		batch.step(0.5)
	h.eq(batch.inventory.count_at(StationModel.FURNACE_OUTPUT_SLOT), 8, "one coal smelts eight items")
	h.eq(batch.inventory.item_at(StationModel.FURNACE_OUTPUT_SLOT), BlockDB.GLASS, "the eight items are glass")
	h.eq(batch.inventory.count_at(StationModel.FURNACE_INPUT_SLOT), 1, "the ninth item is left for the next fuel")
	h.approx(batch.burn_remaining, 0.0, 1e-6, "the coal is spent")

	# A full output slot pauses the cook rather than eating the input.
	var blocked := StationModel.new(StationModel.FURNACE)
	blocked.inventory.insert(StationModel.FURNACE_INPUT_SLOT, {"item": BlockDB.COBBLESTONE, "count": 2})
	blocked.inventory.insert(StationModel.FURNACE_FUEL_SLOT, {"item": ItemDB.COAL, "count": 1})
	blocked.inventory.insert(StationModel.FURNACE_OUTPUT_SLOT, {"item": BlockDB.STONE, "count": 64}, true)
	blocked.step(30.0)
	h.eq(blocked.inventory.count_at(StationModel.FURNACE_OUTPUT_SLOT), 64, "a full output is left alone")
	h.eq(blocked.inventory.count_at(StationModel.FURNACE_INPUT_SLOT), 2, "the input is not consumed while the output is full")
	h.eq(blocked.inventory.count_at(StationModel.FURNACE_FUEL_SLOT), 1, "no fuel is wasted on a blocked cook")

	# A matching output with room keeps smelting into it.
	var topping := StationModel.new(StationModel.FURNACE)
	topping.inventory.insert(StationModel.FURNACE_INPUT_SLOT, {"item": BlockDB.COBBLESTONE, "count": 1})
	topping.inventory.insert(StationModel.FURNACE_FUEL_SLOT, {"item": ItemDB.COAL, "count": 1})
	topping.inventory.insert(StationModel.FURNACE_OUTPUT_SLOT, {"item": BlockDB.STONE, "count": 5}, true)
	topping.step(30.0)
	h.eq(topping.inventory.count_at(StationModel.FURNACE_OUTPUT_SLOT), 6, "the output tops up an existing stack")

	# Progress survives serialisation, so a reload resumes the cook.
	var saved := StationModel.new(StationModel.FURNACE)
	saved.inventory.insert(StationModel.FURNACE_INPUT_SLOT, {"item": BlockDB.SAND, "count": 3})
	saved.inventory.insert(StationModel.FURNACE_FUEL_SLOT, {"item": ItemDB.COAL, "count": 1})
	saved.step(2.0)
	var midway := saved.cook_progress
	h.greater(midway, 0.0, "the furnace is part-way through a cook")
	var payload: Dictionary = saved.to_dictionary()
	var restored := StationModel.new(StationModel.FURNACE)
	h.check(restored.from_dictionary(payload), "a furnace restores from its payload")
	h.approx(restored.cook_progress, midway, 1e-6, "the cook progress is preserved")
	h.approx(restored.burn_remaining, saved.burn_remaining, 1e-6, "the burn time is preserved")
	h.eq(restored.inventory.to_dictionary(), saved.inventory.to_dictionary(), "the contents are preserved")
	h.check(not restored.from_dictionary({"kind": StationModel.TABLE, "inventory": payload["inventory"]}),
		"a payload of the wrong kind is rejected")

	# Furnace serialisation rejects negative timers.
	var bad := payload.duplicate(true)
	bad["burn_remaining"] = -5.0
	h.check(not StationModel.new(StationModel.FURNACE).from_dictionary(bad), "a negative timer is rejected")

	# Determinism: the same steps produce the same state.
	var a := StationModel.new(StationModel.FURNACE)
	var b := StationModel.new(StationModel.FURNACE)
	for f in [a, b]:
		f.inventory.insert(StationModel.FURNACE_INPUT_SLOT, {"item": BlockDB.SAND, "count": 4})
		f.inventory.insert(StationModel.FURNACE_FUEL_SLOT, {"item": ItemDB.COAL, "count": 1})
	for step in 40:
		a.step(0.25)
		b.step(0.25)
	h.eq(a.to_dictionary(), b.to_dictionary(), "identical step sequences give identical furnace state")


# --- registry -------------------------------------------------------------

func _test_registry(h: TestHarness) -> void:
	h.section("station registry")
	var world := _table_world()
	var table_position := Vector3i(4, 100, 4)
	var furnace_position := Vector3i(9, 100, 4)
	_place(world, table_position, BlockDB.CRAFTING_TABLE)
	_place(world, furnace_position, BlockDB.FURNACE)

	var registry = RegistryModel.new(world)
	h.eq(registry.count(), 0, "a fresh registry holds no station state")
	h.check(registry.station_at(Vector3i(20, 100, 20)) == null, "a cell without a station yields null")
	h.eq(registry.count(), 0, "asking about a non-station creates no state")

	var table = registry.station_at(table_position)
	h.check(table != null, "a placed crafting table yields a station")
	h.eq(table.kind, StationModel.TABLE, "the station kind follows the block")
	h.eq(registry.count(), 1, "the station state is created lazily")
	h.check(registry.station_at(table_position) == table, "the same station is returned again")
	h.eq(registry.count(), 1, "asking twice does not create a second state")

	# Two nearby stations keep independent inventories.
	var furnace = registry.station_at(furnace_position)
	h.eq(furnace.kind, StationModel.FURNACE, "the furnace cell yields a furnace station")
	table.inventory.insert(0, {"item": BlockDB.PLANKS, "count": 7})
	h.eq(furnace.inventory.total_items(), 0, "the furnace did not receive the table's items")
	h.eq(registry.count(), 2, "the registry holds both stations")

	# State survives the chunk being unloaded and regenerated.
	var coord := VoxelWorld.world_to_chunk(table_position)
	world.unload_chunk(coord)
	_place(world, table_position, BlockDB.CRAFTING_TABLE)
	h.check(world.has_chunk(coord), "the chunk is loaded again")
	var reloaded = registry.station_at(table_position)
	h.eq(reloaded.inventory.total_of(BlockDB.PLANKS), 7, "the contents survive a chunk unload and reload")

	# A cell that stops being a station drops its stale state.
	world.set_block(furnace_position, BlockDB.STONE)
	h.check(registry.station_at(furnace_position) == null, "a replaced station block yields no station")
	h.check(not registry.has(furnace_position), "the stale state was dropped")
	h.eq(registry.count(), 1, "only the surviving station remains")

	# Destroying a station returns its contents.
	var removed: Array = registry.take_contents(table_position)
	h.eq(removed.size(), 1, "the destroyed station returned its stacks")
	h.eq(int(removed[0]["item"]), BlockDB.PLANKS, "the returned stack is the stored item")
	h.eq(int(removed[0]["count"]), 7, "the returned stack holds every item")
	h.check(not registry.has(table_position), "the station state is gone after destruction")

	# Persistence round-trip, including the furnace's timers.
	var world2 := _table_world()
	var position := Vector3i(6, 100, 6)
	_place(world2, position, BlockDB.FURNACE)
	var registry2 = RegistryModel.new(world2)
	var saved_furnace = registry2.station_at(position)
	saved_furnace.inventory.insert(StationModel.FURNACE_INPUT_SLOT, {"item": BlockDB.SAND, "count": 5})
	saved_furnace.inventory.insert(StationModel.FURNACE_FUEL_SLOT, {"item": ItemDB.COAL, "count": 2})
	saved_furnace.inventory.insert(StationModel.FURNACE_OUTPUT_SLOT, {"item": BlockDB.GLASS, "count": 3}, true)
	saved_furnace.step(3.0)
	var rows: Array = registry2.to_dictionary()
	h.eq(rows.size(), 1, "the registry serialises its stations")

	var registry3 = RegistryModel.new(world2)
	var summary: Dictionary = registry3.from_dictionary(rows)
	h.eq(int(summary["accepted"]), 1, "the station payload is accepted")
	h.eq(int(summary["rejected"]), 0, "no row is rejected")
	var restored = registry3.station_at(position)
	h.eq(restored.inventory.total_of(BlockDB.SAND), 5, "the saved input survives")
	h.eq(restored.inventory.total_of(ItemDB.COAL), 1, "the fuel burned by the step before saving is accounted for")
	h.eq(restored.inventory.total_of(BlockDB.GLASS), 3, "the saved output survives")
	h.approx(restored.cook_progress, saved_furnace.cook_progress, 1e-6, "the saved cook progress survives")

	# Malformed rows are counted and skipped, never applied.
	var bad_rows: Array = [rows[0], ["nope"], [1, 2, 3, {"kind": "not_a_station"}], [9, 9, 9, {"kind": StationModel.FURNACE}]]
	var registry4 = RegistryModel.new(world2)
	var bad_summary: Dictionary = registry4.from_dictionary(bad_rows)
	h.eq(int(bad_summary["accepted"]), 1, "only the valid row is accepted")
	h.eq(int(bad_summary["rejected"]), 3, "the unreadable rows are counted as rejected")

	# Ticking: only loaded furnaces near the focus advance.
	var world3 := _table_world()
	var near := Vector3i(2, 100, 2)
	var far := Vector3i(2, 100, 200)
	_place(world3, near, BlockDB.FURNACE)
	_place(world3, far, BlockDB.FURNACE)
	var registry5 = RegistryModel.new(world3)
	var near_station = registry5.station_at(near)
	var far_station = registry5.station_at(far)
	for station in [near_station, far_station]:
		station.inventory.insert(StationModel.FURNACE_INPUT_SLOT, {"item": BlockDB.SAND, "count": 3})
		station.inventory.insert(StationModel.FURNACE_FUEL_SLOT, {"item": ItemDB.COAL, "count": 1})
	var changed := registry5.tick(0.5, Vector3(2.5, 100.5, 2.5))
	h.greater(float(changed), 0.0, "the near furnace advanced")
	h.greater(near_station.burn_remaining, 0.0, "the near furnace is burning")
	h.approx(far_station.burn_remaining, 0.0, 1e-6, "the far furnace is paused")

	# An unloaded furnace is paused too.
	var coord3 := VoxelWorld.world_to_chunk(near)
	world3.unload_chunk(coord3)
	var burn_before: float = near_station.burn_remaining
	registry5.tick(1.0, Vector3(2.5, 100.5, 2.5))
	h.approx(near_station.burn_remaining, burn_before, 1e-6, "an unloaded furnace is paused")

	# prune() sweeps state for stations whose block changed while unobserved.
	_place(world3, near, BlockDB.FURNACE)
	world3.set_block(far, BlockDB.STONE)
	var removed_positions: Array = registry5.prune()
	h.check(removed_positions.has(far), "prune removes the stale station")
	h.check(not registry5.has(far), "the stale station state is gone")
	h.check(registry5.has(near), "the live station is kept")

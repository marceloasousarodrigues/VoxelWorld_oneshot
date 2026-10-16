extends RefCounted

## Crafting rules (`Crafting`): the fixed recipe list, the can/craft/available
## queries and the atomicity guarantees.
##
## The important behaviour pinned here is that `craft` never consumes an input it
## cannot pay back with the output -- a failed craft (missing ingredients, or a
## full inventory with no room for the output) must leave the inventory
## byte-identical.  This runs against the real `Inventory` model, not a stub.


func name() -> String:
	return "crafting"


## The recipe that produces the given block id, or an empty dictionary.
func _find(output: int) -> Dictionary:
	for recipe in Crafting.recipes():
		if int(recipe["output"]) == output:
			return recipe
	return {}


func run(h: TestHarness) -> void:
	# --- the recipe list -----------------------------------------------------
	var recipes: Array = Crafting.recipes()
	h.check(recipes.size() > 0, "recipes() is not empty")
	h.check(Crafting.recipes() == recipes, "recipes() is deterministic across calls")

	var valid := true
	var order: Array = []
	for recipe in recipes:
		order.append(int(recipe["output"]))
		var inputs: Dictionary = recipe["inputs"]
		if inputs.is_empty():
			valid = false
		for block_id in inputs:
			if int(block_id) < 0 or int(block_id) >= BlockDB.COUNT or int(inputs[block_id]) <= 0:
				valid = false
		var output := int(recipe["output"])
		if output < 0 or output >= BlockDB.COUNT or int(recipe["output_count"]) <= 0:
			valid = false
	h.check(valid, "every recipe references valid block ids with positive counts")
	h.eq(order, [BlockDB.PLANKS, BlockDB.CRAFTING_TABLE, BlockDB.COBBLESTONE, BlockDB.GLASS, BlockDB.BRICK],
		"recipes() keeps its fixed order")

	var oak_planks := _find(BlockDB.PLANKS)
	h.check(not oak_planks.is_empty(), "the Oak Log -> Planks recipe exists")
	h.eq(Crafting.label(oak_planks), "1 Oak Log \u2192 4 Planks",
		"the recipe label reads '1 Oak Log -> 4 Planks'")

	# --- can_craft -----------------------------------------------------------
	h.check(not Crafting.can_craft(Inventory.new(), oak_planks),
		"can_craft is false when an ingredient is missing")
	var one_log := Inventory.new()
	one_log.add(BlockDB.OAK_LOG, 1)
	h.check(Crafting.can_craft(one_log, oak_planks),
		"can_craft is true when the ingredient is present")
	h.check(not Crafting.can_craft(one_log, _find(BlockDB.BRICK)),
		"can_craft is false without the other recipe's ingredient")

	# --- craft consumes exactly the inputs and adds exactly the output -------
	var inv := Inventory.new()
	inv.add(BlockDB.OAK_LOG, 3)
	var result: Dictionary = Crafting.craft(inv, oak_planks)
	h.check(bool(result["ok"]), "craft succeeds when the ingredients are present")
	h.eq(int(result["output"]), BlockDB.PLANKS, "the result reports the output block")
	h.eq(int(result["output_count"]), 4, "the result reports the output count")
	h.eq(inv.count_of(BlockDB.OAK_LOG), 2, "craft consumes exactly one Oak Log")
	h.eq(inv.count_of(BlockDB.PLANKS), 4, "craft adds exactly four Planks")

	# a recipe that needs more than one item removes exactly that many
	var sand_inv := Inventory.new()
	sand_inv.add(BlockDB.SAND, 3)
	var glass_result: Dictionary = Crafting.craft(sand_inv, _find(BlockDB.GLASS))
	h.check(bool(glass_result["ok"]), "a multi-count recipe crafts")
	h.eq(sand_inv.count_of(BlockDB.SAND), 1, "craft consumes exactly the required item count")
	h.eq(sand_inv.count_of(BlockDB.GLASS), 1, "craft adds the recipe output count")

	# --- insufficient ingredients: rejected, inventory unchanged -------------
	var poor := Inventory.new()
	poor.add(BlockDB.OAK_LOG, 1)
	var poor_slots := poor.slots.duplicate()
	var poor_counts := poor.counts.duplicate()
	var short: Dictionary = Crafting.craft(poor, _find(BlockDB.CRAFTING_TABLE))
	h.check(not bool(short["ok"]), "craft fails when the ingredients are insufficient")
	h.check(str(short["reason"]) != "", "the insufficient-ingredient failure reports a reason")
	h.eq(poor.slots, poor_slots, "a failed craft leaves the slot ids unchanged")
	h.eq(poor.counts, poor_counts, "a failed craft leaves the slot counts unchanged")

	# --- full inventory, no room for the output: rejected atomically ---------
	# Nine occupied slots, none holding the output (Planks), and the input slot
	# still holds an item after the craft -- so removing the input frees nothing
	# and there is genuinely nowhere for the output to go.
	var full := Inventory.new()
	for block_id in [BlockDB.GRASS, BlockDB.DIRT, BlockDB.STONE, BlockDB.SAND,
			BlockDB.COBBLESTONE, BlockDB.GLASS, BlockDB.BRICK, BlockDB.CLAY]:
		full.add(block_id, 5)
	full.add(BlockDB.OAK_LOG, 2)
	h.eq(full.used_slots(), Inventory.HOTBAR_SIZE, "the test inventory is full")
	h.check(Crafting.can_craft(full, oak_planks), "the full inventory still holds the ingredients")
	var full_slots := full.slots.duplicate()
	var full_counts := full.counts.duplicate()
	var blocked: Dictionary = Crafting.craft(full, oak_planks)
	h.check(not bool(blocked["ok"]), "craft fails when the output has no room after consumption")
	h.check(str(blocked["reason"]) != "", "the full-inventory failure reports a reason")
	h.eq(full.slots, full_slots, "a rejected craft consumes no inputs (slot ids)")
	h.eq(full.counts, full_counts, "a rejected craft consumes no inputs (slot counts)")

	# --- consuming the inputs may itself free the room the output needs ------
	# The same nine occupied slots, but the Planks stack holds exactly the four
	# the recipe consumes, so removing it empties the slot for the Crafting Table.
	var tight := Inventory.new()
	for block_id in [BlockDB.GRASS, BlockDB.DIRT, BlockDB.STONE, BlockDB.SAND,
			BlockDB.COBBLESTONE, BlockDB.GLASS, BlockDB.BRICK, BlockDB.CLAY]:
		tight.add(block_id, 5)
	tight.add(BlockDB.PLANKS, 4)
	h.eq(tight.used_slots(), Inventory.HOTBAR_SIZE, "the tight inventory is full")
	var table := _find(BlockDB.CRAFTING_TABLE)
	h.check(Crafting.can_craft(tight, table), "the tight inventory holds the planks")
	var freed: Dictionary = Crafting.craft(tight, table)
	h.check(bool(freed["ok"]), "craft succeeds when consuming the inputs frees a slot")
	h.eq(tight.count_of(BlockDB.PLANKS), 0, "the consumed planks are gone")
	h.eq(tight.count_of(BlockDB.CRAFTING_TABLE), 1, "the crafting table took the freed slot")

	# --- output merges into an existing matching stack -----------------------
	var merge := Inventory.new()
	merge.add(BlockDB.PLANKS, 5)
	merge.add(BlockDB.OAK_LOG, 1)
	var merged: Dictionary = Crafting.craft(merge, oak_planks)
	h.check(bool(merged["ok"]), "craft succeeds when a matching stack already exists")
	h.eq(merge.count_of(BlockDB.PLANKS), 9, "the output merges into the existing stack")
	var planks_stacks := 0
	for index in Inventory.HOTBAR_SIZE:
		if merge.slots[index] == BlockDB.PLANKS:
			planks_stacks += 1
	h.eq(planks_stacks, 1, "the output merges into one stack instead of opening a second slot")
	h.eq(merge.used_slots(), 1, "the fully consumed input slot is freed")
	h.eq(merge.count_of(BlockDB.OAK_LOG), 0, "the input is consumed when merging")

	# --- unknown / malformed recipes are rejected without consuming ----------
	var guard := Inventory.new()
	guard.add(BlockDB.OAK_LOG, 5)
	var bad_output: Dictionary = Crafting.craft(guard,
		{"inputs": {BlockDB.OAK_LOG: 1}, "output": 999, "output_count": 1})
	h.check(not bool(bad_output["ok"]), "an unknown output block id is rejected")
	var bad_input: Dictionary = Crafting.craft(guard,
		{"inputs": {-1: 1}, "output": BlockDB.PLANKS, "output_count": 1})
	h.check(not bool(bad_input["ok"]), "an unknown input block id is rejected")
	var bad_count: Dictionary = Crafting.craft(guard,
		{"inputs": {BlockDB.OAK_LOG: 0}, "output": BlockDB.PLANKS, "output_count": 1})
	h.check(not bool(bad_count["ok"]), "a non-positive input count is rejected")
	var bad_empty: Dictionary = Crafting.craft(guard, {})
	h.check(not bool(bad_empty["ok"]), "a malformed recipe is rejected")
	h.eq(guard.count_of(BlockDB.OAK_LOG), 5, "no rejected recipe ever consumes items")

	# An AIR output is rejected before anything is touched, even though an AIR
	# add would otherwise consume inputs and only then report leftover.
	var air_inv := Inventory.new()
	air_inv.add(BlockDB.OAK_LOG, 4)
	var air_slots := air_inv.slots.duplicate()
	var air_counts := air_inv.counts.duplicate()
	var air_result: Dictionary = Crafting.craft(air_inv,
		{"inputs": {BlockDB.OAK_LOG: 1}, "output": BlockDB.AIR, "output_count": 1})
	h.check(not bool(air_result["ok"]), "a recipe that outputs AIR is rejected")
	h.check(str(air_result["reason"]) != "", "the AIR-output rejection carries a reason")
	h.eq(air_inv.count_of(BlockDB.OAK_LOG), 4, "an AIR-output recipe consumes nothing")
	h.eq(air_inv.slots, air_slots, "an AIR-output recipe leaves the slot ids unchanged")
	h.eq(air_inv.counts, air_counts, "an AIR-output recipe leaves the slot counts unchanged")

	# --- available_recipes ---------------------------------------------------
	var mixed := Inventory.new()
	mixed.add(BlockDB.OAK_LOG, 1)
	mixed.add(BlockDB.STONE, 1)
	var available: Array = Crafting.available_recipes(mixed)
	h.check(available.size() >= 2, "available_recipes lists the craftable recipes")
	var all_craftable := true
	for recipe in available:
		if not Crafting.can_craft(mixed, recipe):
			all_craftable = false
	h.check(all_craftable, "every recipe in available_recipes is actually craftable")
	h.eq(Crafting.available_recipes(Inventory.new()).size(), 0,
		"an empty inventory can craft nothing")

	# The returned entries must be copies, not the canonical recipe objects.
	if available.size() >= 1:
		(available[0] as Dictionary)["output_count"] = 999
		var corrupted := false
		for recipe in Crafting.recipes():
			if int(recipe["output_count"]) == 999:
				corrupted = true
		h.check(not corrupted, "mutating an available_recipes entry does not corrupt the canonical list")

	h.finish()

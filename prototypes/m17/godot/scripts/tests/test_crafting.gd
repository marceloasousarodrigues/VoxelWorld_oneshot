extends RefCounted

## Crafting rules (`Crafting`): the data-driven recipe catalogue, the
## can/craft/available queries, station gating, fuel, batch crafting and the
## atomicity guarantees.
##
## The important behaviour pinned here is that a craft never consumes what it
## cannot pay back: a failed craft (missing ingredients or fuel, no station, or an
## inventory with no room for the output) must leave the inventory
## byte-identical.  This runs against the real `Inventory` model, not a stub.

const EPS := 0.0001


func name() -> String:
	return "crafting"


func _recipe(id: String) -> Dictionary:
	return Crafting.recipe(id)


## Fills every remaining slot with a full stack of distinct items.  `seed` items
## are placed first so a test can guarantee an ingredient is present; `seed` item
## ids are not added again by the filler.
func _fill_inventory(inventory: Inventory, seed: Dictionary = {}) -> void:
	for item_id in seed:
		inventory.add(int(item_id), int(seed[item_id]))
	var used := {}
	for item_id in seed:
		used[int(item_id)] = true
	for item_id in range(1, ItemDB.COUNT):
		if inventory.free_slot_count() <= 0:
			break
		if used.has(item_id):
			continue
		inventory.add(item_id, ItemDB.max_stack(item_id))


# --- catalogue -------------------------------------------------------------

func _test_catalogue_integrity(h: TestHarness) -> void:
	var recipes: Array = Crafting.recipes()
	h.greater(float(recipes.size()), 20.0, "the catalogue has a real number of recipes (%d)" % recipes.size())
	h.check(Crafting.recipes() == recipes, "recipes() is deterministic across calls")

	var ids := {}
	var valid := true
	var bad := ""
	for recipe: Dictionary in recipes:
		var id := str(recipe.get("id", ""))
		if id.is_empty() or ids.has(id):
			valid = false
			bad = "bad id %s" % id
		ids[id] = true
		var reason := Crafting.validate(recipe)
		if reason != "":
			valid = false
			bad = "%s: %s" % [id, reason]
	h.check(valid, "every recipe is valid and uniquely identified (%s)" % bad)
	h.check(ids.size() == recipes.size(), "recipe ids are unique")
	h.eq(Crafting.ids().size(), recipes.size(), "ids() lists every recipe")

	# Categories and stations are the ones the interface presents.
	var categories := Crafting.categories()
	h.check(categories.size() >= 4, "the catalogue has several categories (%s)" % ", ".join(categories))
	var in_categories := 0
	for category: String in categories:
		in_categories += Crafting.recipes_in(category).size()
	h.eq(in_categories, recipes.size(), "every recipe belongs to exactly one category")
	h.eq(Crafting.recipes_in("Nonsense").size(), 0, "an unknown category is empty")

	h.eq(Crafting.recipe("planks_oak").get("output"), BlockDB.PLANKS, "a recipe can be looked up by id")
	h.check((Crafting.recipe("nope") as Dictionary).is_empty(), "an unknown id resolves to an empty recipe")
	for id: String in ["timber_frame", "packed_path", "fence", "door", "barrel", "lantern",
			"roof_tile", "planks_birch"]:
		h.check(not (Crafting.recipe(id) as Dictionary).is_empty(), "the M22 building recipe %s exists" % id)
	h.eq(Crafting.recipe("lantern").get("output"), BlockDB.LANTERN, "the lantern recipe outputs a lantern")
	h.eq(Crafting.recipe("roof_tile").get("station"), Crafting.STATION_FURNACE,
		"roof tiles are fired in a furnace")


## Every ingredient of every recipe must be obtainable from the world (a mining
## drop or a previous crafting step).  This is what keeps the progression honest:
## a recipe that needs an item nothing produces is unreachable, and no amount of
## UI would fix it.
func _test_everything_is_reachable(h: TestHarness) -> void:
	var reachable := {}
	for block_id in BlockDB.COUNT:
		if not BlockDB.is_defined(block_id):
			continue
		var drop := ItemDB.drop_for_block(block_id)
		if drop != BlockDB.NO_DROP:
			reachable[drop] = true
	# Leaves and tall grass have deterministic chance drops.
	for x in range(0, 300):
		for block_id: int in [BlockDB.OAK_LEAVES, BlockDB.TALL_GRASS]:
			var bonus := ItemDB.bonus_drop(block_id, x, 70, x * 3 + 1)
			if bonus != BlockDB.NO_DROP:
				reachable[bonus] = true
	# Hunting (a boar/grunt loot table) and farming (a ripe crop) are real sources.
	var loot: Array = CreatureDB.loot_for("boar", Vector3i(4, 70, 4))
	loot.append_array(CreatureDB.loot_for("grunt", Vector3i(5, 70, 5)))
	for row: Dictionary in loot:
		reachable[int(row["item"])] = true
	var crop_loot := Farming.new(17017).harvest_loot(BlockDB.WHEAT_3, Vector3i(4, 70, 4))
	for item_id in crop_loot:
		reachable[int(item_id)] = true
	reachable[ItemDB.WHEAT_SEEDS] = true
	var changed := true
	while changed:
		changed = false
		for recipe: Dictionary in Crafting.recipes():
			if reachable.has(int(recipe["output"])):
				continue
			var ok := true
			for item_id in Crafting.ingredients(recipe):
				if not reachable.has(int(item_id)):
					ok = false
			for item_id in Crafting.fuel(recipe):
				if not reachable.has(int(item_id)):
					ok = false
			if ok:
				reachable[int(recipe["output"])] = true
				changed = true
	var unreachable: Array[String] = []
	for recipe: Dictionary in Crafting.recipes():
		if not reachable.has(int(recipe["output"])):
			unreachable.append(str(recipe["id"]))
	h.eq(unreachable, [], "every recipe output is reachable from mining or other recipes")
	# The three tool tiers and the stations must all be reachable, or the
	# progression claim in the roadmap would be false.
	var expected := [ItemDB.WOOD_PICKAXE, ItemDB.STONE_PICKAXE, ItemDB.IRON_PICKAXE,
		ItemDB.DIAMOND_PICKAXE, ItemDB.IRON_INGOT, BlockDB.FURNACE, BlockDB.GLASS,
		BlockDB.BRICK, ItemDB.STICK, ItemDB.BREAD, ItemDB.GOLDEN_APPLE]
	var missing: Array[String] = []
	for item_id: int in expected:
		if not reachable.has(item_id):
			missing.append(ItemDB.name_of(item_id))
	h.eq(missing, [], "the intended progression chain is reachable (%s)" % ", ".join(missing))


func _test_shaped_and_shapeless(h: TestHarness) -> void:
	var pickaxe := _recipe("wood_pickaxe")
	h.check(pickaxe.has("pattern"), "the pickaxe recipe is shaped")
	h.eq(Crafting.ingredients(pickaxe), {BlockDB.PLANKS: 3, ItemDB.STICK: 2},
		"the shaped pickaxe derives its ingredients from its pattern")

	var planks := _recipe("planks_oak")
	h.check(not planks.has("pattern"), "the log recipe is shapeless")
	h.eq(Crafting.ingredients(planks), {BlockDB.OAK_LOG: 1}, "a shapeless recipe declares its ingredients")

	# Shapes are honoured by `match_grid` even though the interface offers the
	# ingredients as a list.
	h.check(Crafting.match_grid(pickaxe, [
		[BlockDB.PLANKS, BlockDB.PLANKS, BlockDB.PLANKS],
		[BlockDB.AIR, ItemDB.STICK, BlockDB.AIR],
		[BlockDB.AIR, ItemDB.STICK, BlockDB.AIR],
	]), "the pickaxe pattern matches its own grid")
	var shovel := _recipe("wood_shovel")
	h.check(Crafting.match_grid(shovel, [
		[BlockDB.AIR, BlockDB.PLANKS, BlockDB.AIR],
		[BlockDB.AIR, ItemDB.STICK, BlockDB.AIR],
		[BlockDB.AIR, ItemDB.STICK, BlockDB.AIR],
	]), "a shape matches wherever it sits in the grid")
	h.check(not Crafting.match_grid(shovel, [
		[BlockDB.AIR, BlockDB.AIR, BlockDB.AIR],
		[BlockDB.PLANKS, ItemDB.STICK, ItemDB.STICK],
		[BlockDB.AIR, BlockDB.AIR, BlockDB.AIR],
	]), "a rotated shape does not match")
	h.check(not Crafting.match_grid(pickaxe, [
		[BlockDB.PLANKS, BlockDB.PLANKS, ItemDB.STICK],
		[BlockDB.PLANKS, BlockDB.PLANKS, ItemDB.STICK],
		[BlockDB.AIR, BlockDB.AIR, BlockDB.AIR],
	]), "a permuted shape does not match")
	h.check(Crafting.match_grid(planks, [
		[BlockDB.OAK_LOG, BlockDB.AIR, BlockDB.AIR],
		[BlockDB.AIR, BlockDB.AIR, BlockDB.AIR],
		[BlockDB.AIR, BlockDB.AIR, BlockDB.AIR],
	]), "a shapeless recipe matches wherever the items are")

	# Minecraft-shaped recipes may be mirrored horizontally (an axe can be
	# crafted in either orientation), but not rotated.
	var axe := _recipe("wood_axe")
	h.check(Crafting.match_grid(axe, [
		[BlockDB.PLANKS, BlockDB.PLANKS, BlockDB.AIR],
		[BlockDB.PLANKS, ItemDB.STICK, BlockDB.AIR],
		[BlockDB.AIR, ItemDB.STICK, BlockDB.AIR],
	]), "the axe pattern matches its declared orientation")
	h.check(Crafting.match_grid(axe, [
		[BlockDB.AIR, BlockDB.PLANKS, BlockDB.PLANKS],
		[BlockDB.AIR, ItemDB.STICK, BlockDB.PLANKS],
		[BlockDB.AIR, ItemDB.STICK, BlockDB.AIR],
	]), "the axe pattern also matches its horizontal mirror")
	h.check(not Crafting.match_grid(axe, [
		[BlockDB.AIR, BlockDB.AIR, BlockDB.AIR],
		[BlockDB.AIR, BlockDB.PLANKS, BlockDB.PLANKS],
		[ItemDB.STICK, BlockDB.PLANKS, ItemDB.STICK],
	]), "a rotated axe shape does not match")


func _test_validate_rejects(h: TestHarness) -> void:
	var cases := [
		[{}, "an empty recipe"],
		[{"id": "x", "category": "Basics", "station": "hand", "inputs": {BlockDB.OAK_LOG: 1},
			"output": BlockDB.AIR, "output_count": 1}, "an AIR output"],
		[{"id": "x", "category": "Basics", "station": "hand", "inputs": {BlockDB.OAK_LOG: 1},
			"output": 999, "output_count": 1}, "an unknown output"],
		[{"id": "x", "category": "Basics", "station": "hand", "inputs": {BlockDB.OAK_LOG: 1},
			"output": BlockDB.PLANKS, "output_count": 0}, "a non-positive output count"],
		[{"id": "x", "category": "Basics", "station": "hand", "inputs": {},
			"output": BlockDB.PLANKS, "output_count": 1}, "an empty ingredient list"],
		[{"id": "x", "category": "Basics", "station": "hand", "inputs": {-3: 1},
			"output": BlockDB.PLANKS, "output_count": 1}, "an unknown input"],
		[{"id": "x", "category": "Basics", "station": "hand", "inputs": {BlockDB.OAK_LOG: 0},
			"output": BlockDB.PLANKS, "output_count": 1}, "a non-positive input count"],
		[{"id": "x", "category": "Basics", "station": "spaceship", "inputs": {BlockDB.OAK_LOG: 1},
			"output": BlockDB.PLANKS, "output_count": 1}, "an unknown station"],
		[{"id": "x", "category": "Basics", "station": "hand",
			"pattern": ["PPPP"], "key": {"P": BlockDB.PLANKS},
			"output": BlockDB.PLANKS, "output_count": 1}, "a pattern wider than three columns"],
		[{"id": "x", "category": "Basics", "station": "hand",
			"pattern": ["P ", " Z"], "key": {"P": BlockDB.PLANKS},
			"output": BlockDB.PLANKS, "output_count": 1}, "a pattern character with no key entry"],
		[{"id": "x", "category": "Basics", "station": "hand",
			"pattern": ["P"], "key": {"P": 999},
			"output": BlockDB.PLANKS, "output_count": 1}, "a key entry that is not an item"],
		[{"id": "x", "category": "Basics", "station": "hand",
			"pattern": ["P"], "key": {"P": BlockDB.PLANKS}, "inputs": {BlockDB.PLANKS: 1},
			"output": BlockDB.PLANKS, "output_count": 1}, "both a pattern and inputs"],
		[{"id": "x", "category": "Basics", "station": "hand",
			"pattern": ["  ", "  "], "key": {"P": BlockDB.PLANKS},
			"output": BlockDB.PLANKS, "output_count": 1}, "a pattern with no items"],
		[{"id": "x", "category": "Basics", "station": "hand", "inputs": {BlockDB.OAK_LOG: 1},
			"fuel": {ItemDB.COAL: 0}, "output": BlockDB.PLANKS, "output_count": 1},
			"a non-positive fuel count"],
		[{"id": "x", "category": "Basics", "station": "hand", "inputs": {BlockDB.OAK_LOG: 1},
			"fuel": {ItemDB.COAL: 1}, "output": BlockDB.PLANKS, "output_count": 1},
			"fuel on a non-smelting recipe"],
	]
	for case: Array in cases:
		h.check(Crafting.validate(case[0]) != "", "validate rejects %s" % case[1])


# --- crafting --------------------------------------------------------------

func _test_can_craft_and_consume(h: TestHarness) -> void:
	var planks := _recipe("planks_oak")
	h.check(not Crafting.can_craft(Inventory.new(), planks), "can_craft is false without the ingredient")

	var inventory := Inventory.new()
	inventory.add(BlockDB.OAK_LOG, 3)
	h.check(Crafting.can_craft(inventory, planks), "can_craft is true with the ingredient")
	var result: Dictionary = Crafting.craft(inventory, planks)
	h.check(bool(result["ok"]), "the craft succeeds")
	h.eq(int(result["output"]), BlockDB.PLANKS, "the result reports the output item")
	h.eq(int(result["output_count"]), 4, "the result reports the output count")
	h.eq(inventory.count_of(BlockDB.OAK_LOG), 2, "exactly one log was consumed")
	h.eq(inventory.count_of(BlockDB.PLANKS), 4, "exactly four planks were added")

	# A recipe that needs a station is refused without one and allowed with it.
	inventory.add(BlockDB.COBBLESTONE, 8)
	var gated_recipe := _recipe("furnace")
	h.check(not Crafting.can_craft(inventory, gated_recipe), "a table recipe is refused without a table")
	h.check(Crafting.can_craft(inventory, gated_recipe, Crafting.STATION_TABLE),
		"the same recipe is allowed with a table")
	var gated: Dictionary = Crafting.craft(inventory, gated_recipe)
	h.check(not bool(gated["ok"]), "crafting a table recipe without a table fails")
	h.check(str(gated["reason"]).to_lower().contains("table"), "the failure explains the missing table")

	# A furnace also serves as a work surface.
	var smelt := _recipe("iron_ingot")
	h.check(Crafting.station_satisfied(smelt, Crafting.STATION_FURNACE), "a furnace satisfies smelting")
	h.check(Crafting.station_satisfied(gated_recipe, Crafting.STATION_FURNACE),
		"a furnace also satisfies a crafting-table recipe")
	h.check(not Crafting.station_satisfied(smelt, Crafting.STATION_TABLE),
		"a crafting table does not satisfy a smelting recipe")
	h.check(not Crafting.station_satisfied(gated_recipe, Crafting.STATION_HAND),
		"hand does not satisfy a table recipe")


func _test_multi_count_and_merging(h: TestHarness) -> void:
	var axe := _recipe("stone_axe")
	h.eq(Crafting.ingredients(axe), {BlockDB.COBBLESTONE: 3, ItemDB.STICK: 2}, "the stone axe needs 3 cobble and 2 sticks")
	var inventory := Inventory.new()
	inventory.add(BlockDB.COBBLESTONE, 3)
	inventory.add(ItemDB.STICK, 2)
	h.check(Crafting.can_craft(inventory, axe, Crafting.STATION_TABLE), "the axe is craftable with a table")
	var result: Dictionary = Crafting.craft(inventory, axe, Crafting.STATION_TABLE)
	h.check(bool(result["ok"]), "the axe crafts")
	h.eq(inventory.count_of(ItemDB.STONE_AXE), 1, "the tool was added")
	h.eq(inventory.count_of(BlockDB.COBBLESTONE), 0, "the cobblestone was consumed exactly")
	h.eq(inventory.count_of(ItemDB.STICK), 0, "the sticks were consumed exactly")
	h.eq(inventory.durability_of(0), ItemDB.max_durability(ItemDB.STONE_AXE),
		"a crafted tool arrives at full durability")
	h.eq(inventory.used_slots(), 1, "the consumed slots were freed")

	# Merging into an existing stack instead of opening a slot.
	var merge := Inventory.new()
	merge.add(BlockDB.PLANKS, 7)
	merge.add(BlockDB.OAK_LOG, 1)
	Crafting.craft(merge, _recipe("planks_oak"))
	h.eq(merge.count_of(BlockDB.PLANKS), 11, "the output merges into the existing stack")
	var stacks := 0
	for index in Inventory.HOTBAR_SIZE:
		if merge.slots[index] == BlockDB.PLANKS:
			stacks += 1
	h.eq(stacks, 1, "the output did not open a second planks slot")


func _test_fuel(h: TestHarness) -> void:
	var smelt := _recipe("iron_ingot")
	h.eq(Crafting.fuel(smelt), {ItemDB.COAL: 1}, "smelting one iron lump costs one coal")
	h.eq(Crafting.station_of(smelt), Crafting.STATION_FURNACE, "smelting happens at a furnace")

	var no_fuel := Inventory.new()
	no_fuel.add(ItemDB.IRON_LUMP, 1)
	h.check(not Crafting.can_craft(no_fuel, smelt, Crafting.STATION_FURNACE), "smelting needs coal")
	h.eq(Crafting.missing(no_fuel, smelt, Crafting.STATION_FURNACE), {ItemDB.COAL: 1},
		"the missing report names the fuel")
	var before := no_fuel.to_dictionary()
	var failed: Dictionary = Crafting.craft(no_fuel, smelt, Crafting.STATION_FURNACE)
	h.check(not bool(failed["ok"]), "smelting without fuel fails")
	h.eq(no_fuel.to_dictionary(), before, "a fuel-short smelt consumes nothing")

	no_fuel.add(ItemDB.COAL, 1)
	h.check(Crafting.can_craft(no_fuel, smelt, Crafting.STATION_FURNACE), "it smelts with coal")
	var smelted: Dictionary = Crafting.craft(no_fuel, smelt, Crafting.STATION_FURNACE)
	h.check(bool(smelted["ok"]), "the smelt succeeds")
	h.eq(no_fuel.count_of(ItemDB.IRON_INGOT), 1, "the ingot was produced")
	h.eq(no_fuel.count_of(ItemDB.IRON_LUMP), 0, "the ore was consumed")
	h.eq(no_fuel.count_of(ItemDB.COAL), 0, "the fuel was consumed")
	h.eq(Crafting.missing(no_fuel, smelt, Crafting.STATION_FURNACE), {ItemDB.IRON_LUMP: 1, ItemDB.COAL: 1},
		"the missing report lists both the input and the fuel once both are gone")


func _test_craftable_count_and_batch(h: TestHarness) -> void:
	var planks := _recipe("planks_oak")
	var inventory := Inventory.new()
	inventory.add(BlockDB.OAK_LOG, 5)
	h.eq(Crafting.craftable_count(inventory, planks), 5, "five logs allow five crafts")
	h.check(Crafting.can_craft_times(inventory, planks, 5, Crafting.STATION_HAND),
		"a five-craft batch fits in the inventory")

	var batch: Dictionary = Crafting.craft_many(inventory, planks, 3)
	h.check(bool(batch["ok"]), "a three-craft batch succeeds")
	h.eq(int(batch["crafted"]), 3, "the batch reports three crafts")
	h.eq(inventory.count_of(BlockDB.OAK_LOG), 2, "the batch consumed three logs")
	h.eq(inventory.count_of(BlockDB.PLANKS), 12, "the batch produced twelve planks")
	h.eq(Crafting.craftable_count(inventory, planks), 2, "the count follows the remaining ingredients")

	var before := inventory.to_dictionary()
	var too_many: Dictionary = Crafting.craft_many(inventory, planks, 99)
	h.check(not bool(too_many["ok"]), "a batch larger than the ingredients allows fails wholly")
	h.check(str(too_many["reason"]) != "", "the failed batch explains why")
	h.eq(inventory.to_dictionary(), before, "a failed batch consumes nothing")

	var zero: Dictionary = Crafting.craft_many(inventory, planks, 0)
	h.check(not bool(zero["ok"]), "a zero-sized batch is rejected")
	h.eq(inventory.to_dictionary(), before, "a zero-sized batch consumes nothing")

	# The batch also has to fit: the same ingredients that allow 64 crafts are
	# refused when the output has nowhere to go, and nothing is consumed.
	var crammed := Inventory.new()
	_fill_inventory(crammed, {BlockDB.OAK_LOG: 64})
	h.eq(crammed.free_slot_count(), 0, "the batch inventory has no free slot")
	h.eq(Crafting.craftable_count(crammed, planks), 64, "the ingredients still allow 64 crafts")
	h.check(not Crafting.can_craft_times(crammed, planks, 1, Crafting.STATION_HAND),
		"one craft is refused because the planks have nowhere to go")
	var crammed_before := crammed.to_dictionary()
	var overflow: Dictionary = Crafting.craft_many(crammed, planks, 1)
	h.check(not bool(overflow["ok"]), "the refused batch reports failure")
	h.eq(crammed.to_dictionary(), crammed_before, "the refused batch consumes nothing")


func _test_atomicity(h: TestHarness) -> void:
	var planks := _recipe("planks_oak")
	var poor := Inventory.new()
	poor.add(BlockDB.OAK_LOG, 0)
	var poor_before := poor.to_dictionary()
	var short: Dictionary = Crafting.craft(poor, planks)
	h.check(not bool(short["ok"]), "a craft without the ingredients fails")
	h.check(str(short["reason"]) != "", "the failure reports a reason")
	h.eq(poor.to_dictionary(), poor_before, "a failed craft leaves the inventory untouched")

	# A full inventory with no room for the output is rejected atomically, even
	# though consuming the input happens first in the implementation.
	var full := Inventory.new()
	_fill_inventory(full, {BlockDB.OAK_LOG: 2})
	h.eq(full.used_slots(), Inventory.SIZE, "the test inventory is full")
	h.eq(Crafting.missing(full, planks), {}, "the full inventory holds every ingredient")
	h.check(not Crafting.can_craft(full, planks), "the craft is refused because the output has no room")
	var full_before := full.to_dictionary()
	var blocked: Dictionary = Crafting.craft(full, planks)
	h.check(not bool(blocked["ok"]), "a craft with no room for the output fails")
	h.check(str(blocked["reason"]).to_lower().contains("room") or
		str(blocked["reason"]).to_lower().contains("full"), "the failure explains the lack of room")
	h.eq(full.to_dictionary(), full_before, "a rejected craft consumes nothing")

	# Consuming the input is allowed to free the slot the output needs.
	var tight := Inventory.new()
	_fill_inventory(tight, {BlockDB.PLANKS: 2, ItemDB.STICK: 0})
	h.eq(tight.used_slots(), Inventory.SIZE, "the tight inventory is full")
	h.eq(tight.free_slot_count(), 0, "the tight inventory has no free slot")
	var freed: Dictionary = Crafting.craft(tight, _recipe("sticks"))
	h.check(bool(freed["ok"]), "a craft succeeds when consuming the input frees a slot")
	h.eq(tight.count_of(ItemDB.STICK), 4, "the sticks landed in the freed slot")
	h.eq(tight.count_of(BlockDB.PLANKS), 0, "the planks were consumed exactly")

	# A slot that is nearly full but has no room for the whole output is not
	# treated as space: the capacity check must respect the stack cap.
	var cramped := Inventory.new()
	_fill_inventory(cramped, {BlockDB.PLANKS: 62, BlockDB.OAK_LOG: 2})
	h.eq(cramped.used_slots(), Inventory.SIZE, "the cramped inventory is full")
	h.eq(cramped.count_of(BlockDB.PLANKS), 62, "the planks stack holds 62")
	var cramped_before := cramped.to_dictionary()
	var cramped_result: Dictionary = Crafting.craft(cramped, planks)
	h.check(not bool(cramped_result["ok"]),
		"a 4-item output does not fit into a stack with 2 room and no free slot")
	h.eq(cramped.to_dictionary(), cramped_before, "the cramped craft consumed nothing")


func _test_available_recipes(h: TestHarness) -> void:
	var inventory := Inventory.new()
	inventory.add(BlockDB.OAK_LOG, 4)
	inventory.add(BlockDB.STONE, 4)
	inventory.add(BlockDB.COBBLESTONE, 8)
	var hand: Array = Crafting.available_recipes(inventory, Crafting.STATION_HAND)
	var all_ok := true
	for recipe: Dictionary in hand:
		if not Crafting.can_craft(inventory, recipe, Crafting.STATION_HAND):
			all_ok = false
		if Crafting.station_of(recipe) != Crafting.STATION_HAND:
			all_ok = false
	h.check(all_ok, "available_recipes only lists craftable hand recipes")
	h.greater(float(hand.size()), 0.0, "the test inventory can craft something by hand")

	var with_table: Array = Crafting.available_recipes(inventory, Crafting.STATION_TABLE)
	h.check(with_table.size() > hand.size(), "a crafting table makes more recipes available")
	h.eq(Crafting.available_recipes(Inventory.new(), Crafting.STATION_FURNACE).size(), 0,
		"an empty inventory can craft nothing")

	# The returned entries must be copies, not the canonical recipe objects.
	if not hand.is_empty():
		(hand[0] as Dictionary)["output_count"] = 999
		var corrupted := false
		for recipe: Dictionary in Crafting.recipes():
			if int(recipe["output_count"]) == 999:
				corrupted = true
		h.check(not corrupted, "mutating an available_recipes entry does not corrupt the catalogue")


func _test_labels(h: TestHarness) -> void:
	var label := Crafting.label(_recipe("planks_oak"))
	h.check(label.contains("Oak Log"), "the label names the ingredient (%s)" % label)
	h.check(label.contains("Planks"), "the label names the output (%s)" % label)
	h.check(label.contains("4"), "the label names the output count (%s)" % label)
	var smelt := Crafting.label(_recipe("iron_ingot"))
	h.check(smelt.to_lower().contains("coal"), "the smelting label mentions the fuel (%s)" % smelt)
	h.check(smelt.to_lower().contains("furnace"), "the smelting label mentions the furnace (%s)" % smelt)


# --- stations --------------------------------------------------------------

func _test_best_station(h: TestHarness) -> void:
	var world := VoxelWorld.new(17017)
	var chunk := ChunkData.new(Vector3i.ZERO)
	chunk.generated = true
	world.adopt_chunk(chunk)
	var origin := Vector3i(8, 8, 8)
	h.eq(Crafting.best_station(world, origin, 3), Crafting.STATION_HAND, "an empty world offers no station")

	world.set_block(Vector3i(10, 8, 8), BlockDB.CRAFTING_TABLE)
	h.eq(Crafting.best_station(world, origin, 3), Crafting.STATION_TABLE, "a nearby table is found")
	h.eq(Crafting.best_station(world, origin, 1), Crafting.STATION_HAND, "a table outside the radius is not found")
	h.eq(Crafting.best_station(world, Vector3i(40, 40, 40), 3), Crafting.STATION_HAND,
		"a far focus sees no station")

	world.set_block(Vector3i(9, 8, 8), BlockDB.FURNACE)
	h.eq(Crafting.best_station(world, origin, 3), Crafting.STATION_FURNACE,
		"the best available station wins")
	world.set_block(Vector3i(9, 8, 8), BlockDB.AIR)
	h.eq(Crafting.best_station(world, origin, 3), Crafting.STATION_TABLE, "removing the furnace falls back to the table")


func run(h: TestHarness) -> void:
	_test_catalogue_integrity(h)
	_test_everything_is_reachable(h)
	_test_shaped_and_shapeless(h)
	_test_validate_rejects(h)
	_test_can_craft_and_consume(h)
	_test_multi_count_and_merging(h)
	_test_fuel(h)
	_test_craftable_count_and_batch(h)
	_test_atomicity(h)
	_test_available_recipes(h)
	_test_labels(h)
	_test_best_station(h)
	h.finish()

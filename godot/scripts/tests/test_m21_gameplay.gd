extends RefCounted

## M21 gameplay-depth regression module.
##
## Pins the systems that make the existing mechanics connect: species-specific
## creature loot, cooking as a real furnace chain, wheat farming (plant → grow →
## harvest → replant), bone meal as a hunting/farming link, and the persistent
## storage chest.  These are model-level tests; `run_integration.gd` drives the
## same paths through the real scene.


func name() -> String:
	return "M21 gameplay depth"


func run(h: TestHarness) -> void:
	_test_creature_loot(h)
	_test_cooking_chain(h)
	_test_farming(h)
	_test_storage_chest(h)
	h.finish()


func _test_creature_loot(h: TestHarness) -> void:
	h.section("M21 species-specific loot")
	for species: String in ["boar", "grunt"]:
		h.check(CreatureDB.has_species(species), "%s has a definition" % species)
		var loot: Array = CreatureDB.loot_for(species, Vector3i(3, 70, 4))
		h.eq(loot, CreatureDB.loot_for(species, Vector3i(3, 70, 4)),
			"%s loot is deterministic for a kill cell" % species)
		var items: Array = []
		for row: Dictionary in loot:
			items.append(int(row["item"]))
			h.check(int(row["count"]) > 0, "%s loot rows have a positive count" % species)
			h.check(ItemDB.is_valid(int(row["item"])), "%s loot item is valid" % species)
		h.check(not items.has(BlockDB.OAK_LOG), "%s never drops an Oak Log" % species)
	h.check(CreatureDB.loot_for("boar", Vector3i(1, 70, 1)).size() >= 2,
		"a boar always drops meat and hide")
	var boar_loot: Array = CreatureDB.loot_for("boar", Vector3i(1, 70, 1))
	var boar_items: Array = []
	for row: Dictionary in boar_loot:
		boar_items.append(int(row["item"]))
	h.check(boar_items.has(ItemDB.RAW_MEAT), "boar loot includes raw meat")
	h.check(boar_items.has(ItemDB.HIDE), "boar loot includes hide")
	h.check(CreatureDB.loot_total(boar_loot) >= 2, "a boar kill is worth hunting")
	var grunt_items: Array = []
	for row: Dictionary in CreatureDB.loot_for("grunt", Vector3i(2, 70, 2)):
		grunt_items.append(int(row["item"]))
	h.check(grunt_items.has(ItemDB.BONE), "grunt loot includes bone")
	h.eq(CreatureDB.name_of("boar"), "Boar", "the species name is data-driven")


func _test_cooking_chain(h: TestHarness) -> void:
	h.section("M21 cooking chain")
	var recipe := Smelting.recipe_for(ItemDB.RAW_MEAT)
	h.check(not recipe.is_empty(), "raw meat is a furnace input")
	if not recipe.is_empty():
		h.eq(int(recipe["output"]), ItemDB.COOKED_MEAT, "raw meat smelts into cooked meat")
		h.check(Smelting.cook_seconds(recipe) > 0.0, "cooking takes time")
		h.check(Crafting.validate(recipe) == "", "the cooking recipe is valid")
	h.check(Smelting.is_fuel(ItemDB.COAL), "coal is a fuel")
	h.check(ItemDB.food_value(ItemDB.COOKED_MEAT) > ItemDB.food_value(ItemDB.RAW_MEAT),
		"cooked meat restores more hunger than raw meat")

	# Run the real timed furnace: one raw meat + coal -> one cooked meat, and the
	# input/fuel are consumed exactly once.
	var furnace := Station.new(Station.FURNACE)
	furnace.inventory.insert(Station.FURNACE_INPUT_SLOT, {"item": ItemDB.RAW_MEAT, "count": 1})
	furnace.inventory.insert(Station.FURNACE_FUEL_SLOT, {"item": ItemDB.COAL, "count": 1})
	h.check(furnace.step(0.1), "the furnace starts working with meat and fuel")
	furnace.step(Smelting.cook_seconds(recipe) + 0.2)
	h.eq(furnace.inventory.total_of(ItemDB.COOKED_MEAT), 1, "one meat was cooked")
	h.eq(furnace.inventory.total_of(ItemDB.RAW_MEAT), 0, "the raw meat was consumed")
	h.eq(furnace.inventory.total_of(ItemDB.COAL), 0, "one coal was burned")
	h.check(furnace.inventory.total_of(ItemDB.COOKED_MEAT) == 1,
		"the furnace produced the output exactly once")

	var effect: Dictionary = Survival.food_effect(5.0, ItemDB.food_value(ItemDB.COOKED_MEAT),
		ItemDB.heal_value(ItemDB.COOKED_MEAT))
	h.check(bool(effect["improved"]), "cooked meat is a real meal")
	h.greater(float(effect["hunger"]), 5.0, "eating cooked meat restores hunger")

	# Leaves are a real, weak furnace fuel: three two-second leaves are needed to
	# finish one six-second cook.
	var leaf_furnace := Station.new(Station.FURNACE)
	leaf_furnace.inventory.insert(Station.FURNACE_INPUT_SLOT,
		{"item": BlockDB.SAND, "count": 1})
	leaf_furnace.inventory.insert(Station.FURNACE_FUEL_SLOT,
		{"item": BlockDB.OAK_LEAVES, "count": 3})
	for step in 3:
		leaf_furnace.step(2.0)
	h.eq(leaf_furnace.inventory.total_of(BlockDB.GLASS), 1,
		"leaves burn long enough to smelt glass")
	h.eq(leaf_furnace.inventory.total_of(BlockDB.OAK_LEAVES), 0,
		"one six-second cook consumes three leaves")


func _test_farming(h: TestHarness) -> void:
	h.section("M21 wheat farming")
	var world := VoxelWorld.new(17017)
	var soil := Vector3i(8, 70, 8)
	world.ensure_chunk(VoxelWorld.world_to_chunk(soil))
	h.check(world.set_block(soil, BlockDB.GRASS), "a grass soil cell is placed")
	world.set_block(soil + Vector3i.UP, BlockDB.AIR)
	h.eq(world.get_block(soil + Vector3i.UP), BlockDB.AIR, "the crop cell is clear")
	var farming := Farming.new(17017)
	var decision: Dictionary = farming.plant(world, soil)
	h.check(bool(decision["ok"]), "wheat can be planted on grass")
	h.eq(world.get_block(soil), BlockDB.FARMLAND, "planting tills the soil to farmland")
	h.eq(world.get_block(soil + Vector3i.UP), BlockDB.WHEAT_0, "a stage-0 crop is placed above it")
	h.eq(farming.count(), 1, "the crop's growth progress is tracked")

	# A refused plant changes nothing: an occupied cell cannot be planted twice.
	var refused: Dictionary = farming.plant(world, soil)
	h.check(not bool(refused["ok"]), "an occupied crop cell refuses a second planting")

	# Growth advances through every stage while the player is nearby.
	var crop := soil + Vector3i.UP
	for stage in range(1, 4):
		farming.step(Farming.STAGE_SECONDS + 0.01, world, Vector3(8.5, 70.0, 8.5))
		h.eq(world.get_block(crop), Farming.block_for_stage(stage),
			"the crop advances to stage %d" % stage)
	h.eq(world.get_block(crop), BlockDB.WHEAT_3, "the crop becomes ripe")
	h.check(not farming.progress.has(crop), "a ripe crop stops tracking growth")

	# Harvest is deterministic and gives both food and a replanting seed.
	var loot: Dictionary = farming.harvest_loot(BlockDB.WHEAT_3, crop)
	h.check(int(loot.get(ItemDB.WHEAT, 0)) >= 2, "a ripe crop yields at least two wheat")
	h.check(int(loot.get(ItemDB.WHEAT_SEEDS, 0)) >= 1, "a ripe crop yields seeds to replant")
	h.eq(loot, farming.harvest_loot(BlockDB.WHEAT_3, crop), "crop loot is deterministic")
	var young: Dictionary = farming.harvest_loot(BlockDB.WHEAT_0, crop)
	h.eq(int(young.get(ItemDB.WHEAT_SEEDS, 0)), 1, "an immature crop returns one seed")

	# Breaking the crop itself and replanting works, and an unsupported crop is
	# cleared rather than left floating.
	h.check(world.set_block(crop, BlockDB.AIR), "the ripe crop is harvested")
	h.check(bool(farming.plant(world, soil)["ok"]), "the plot can be replanted")
	h.check(world.set_block(soil, BlockDB.AIR), "the farmland under a crop is removed")
	farming.step(0.1, world, Vector3(8.5, 70.0, 8.5))
	h.eq(world.get_block(crop), BlockDB.AIR, "a crop without soil is removed")
	h.eq(farming.count(), 0, "the unsupported crop's progress is forgotten")

	# Bone meal advances a growing crop one stage; a ripe crop refuses it.
	h.check(world.set_block(soil, BlockDB.FARMLAND), "farmland is restored")
	h.check(bool(farming.plant(world, soil)["ok"]), "the plot is planted again")
	h.check(farming.fertilize(world, crop), "bone meal advances a growing crop")
	h.eq(world.get_block(crop), BlockDB.WHEAT_1, "bone meal moved the crop one stage")
	farming.fertilize(world, crop)
	farming.fertilize(world, crop)
	h.eq(world.get_block(crop), BlockDB.WHEAT_3, "bone meal can finish a crop")
	h.check(not farming.fertilize(world, crop), "a ripe crop refuses bone meal")

	# Progress round-trips through the persistence format.
	var payload := farming.to_dictionary()
	var restored := Farming.new(17017)
	h.eq(int(restored.from_dictionary(payload)["accepted"]), payload.size(),
		"crop growth progress round-trips")
	h.eq(restored.to_dictionary(), payload, "the restored crop payload is identical")

	# Seeds are obtainable without a starter kit, from tall grass.
	var found_seed := false
	for x in range(0, 300):
		if ItemDB.bonus_drop(BlockDB.TALL_GRASS, x, 70, x * 3) == ItemDB.WHEAT_SEEDS:
			found_seed = true
			break
	h.check(found_seed, "tall grass can supply the first wheat seeds")


func _test_storage_chest(h: TestHarness) -> void:
	h.section("M21 persistent storage chest")
	var chest := Station.new(Station.CHEST)
	h.check(chest.is_storage(), "the chest is a storage station")
	h.eq(chest.inventory.size(), Station.CHEST_SLOTS, "the chest has 27 slots")
	h.eq(chest.inventory.deposit({"item": BlockDB.COBBLESTONE, "count": 64}), 0,
		"a stack fits in the chest")
	h.eq(chest.inventory.deposit({"item": ItemDB.IRON_INGOT, "count": 8}), 0,
		"a material stack fits in the chest")
	h.eq(chest.inventory.total_of(BlockDB.COBBLESTONE), 64, "the chest holds the exact count")
	h.eq(chest.inventory.total_of(ItemDB.IRON_INGOT), 8, "the chest holds each item separately")
	var payload := chest.to_dictionary()
	var restored := Station.new(Station.CHEST)
	h.check(restored.from_dictionary(payload), "chest contents round-trip")
	h.eq(restored.inventory.total_of(BlockDB.COBBLESTONE), 64, "the chest's cobblestone survived")
	h.eq(restored.inventory.total_of(ItemDB.IRON_INGOT), 8, "the chest's iron survived")
	h.eq(chest.label(), "Storage Chest", "the chest has a station label")
	h.check(Station.is_station_block(BlockDB.CHEST), "the chest is a world-object station")
	h.eq(Station.kind_for_block(BlockDB.CHEST), Station.CHEST, "the chest block maps to the storage kind")

	# The chest is a real crafting-table recipe: eight planks, one chest.
	var inventory := Inventory.new()
	inventory.add(BlockDB.PLANKS, 8)
	var crafted: Dictionary = Crafting.craft(inventory, Crafting.recipe("chest"), Crafting.STATION_TABLE)
	h.check(bool(crafted["ok"]), "eight planks craft a chest at a crafting table")
	h.eq(inventory.count_of(BlockDB.CHEST), 1, "the craft produced exactly one chest")
	h.eq(inventory.count_of(BlockDB.PLANKS), 0, "the craft consumed exactly eight planks")
	h.check(not bool(Crafting.craft(inventory, Crafting.recipe("chest"), Crafting.STATION_HAND)["ok"]),
		"a chest needs a crafting table, not the hand")

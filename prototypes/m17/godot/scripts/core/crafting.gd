class_name Crafting
extends RefCounted

## Data-driven crafting rules for the M17 Godot voxel game.
##
## This is the engine-independent model: a fixed, ordered recipe catalogue plus
## the queries the game and its crafting interface need.  It never touches the
## scene tree or the voxel world -- it only reads and mutates the player's
## `Inventory`, which is itself node-free and serialisable.
##
## A recipe is a dictionary:
##
##     {
##       "id": "wood_pickaxe",              # unique, stable
##       "category": "Tools",               # interface grouping
##       "station": "table",                # "hand" | "table" | "furnace"
##       "pattern": ["PPP", " S ", " S "],  # optional shaped form (max 3x3)
##       "key": {"P": BlockDB.PLANKS, "S": ItemDB.STICK},
##       "inputs": { item_id: count, ... }, # required when there is no pattern
##       "fuel": { ItemDB.COAL: 1 },        # smelting only
##       "output": item_id,
##       "output_count": int,
##     }
##
## A shaped recipe declares its ingredients through `pattern`/`key` and
## `ingredients()` derives the multiset from it, so the two can never disagree.
## The interface offers the ingredients as a list (fast to use repeatedly), but
## `match_grid()` implements the real shape semantics and the meta-tests pin the
## two together.
##
## `craft()` and `craft_many()` are atomic: they validate the recipe, the station,
## the ingredients, the fuel and the room for the output *after* the inputs would
## be consumed -- all against a scratch copy -- before touching the inventory.  A
## craft that cannot complete leaves the inventory byte-identical.

const STATION_HAND := "hand"
const STATION_TABLE := "table"
const STATION_FURNACE := "furnace"
## A better station also serves the simpler ones (a furnace is also a work
## surface), so a player never has to carry both.
const STATION_RANK := {STATION_HAND: 0, STATION_TABLE: 1, STATION_FURNACE: 2}

static var _recipes: Array = []
static var _by_id: Dictionary = {}
static var _categories: Array = []


static func _static_init() -> void:
	_recipes = _build_catalogue()
	_by_id.clear()
	_categories.clear()
	for recipe: Dictionary in _recipes:
		_by_id[str(recipe["id"])] = recipe
		var category := str(recipe["category"])
		if not _categories.has(category):
			_categories.append(category)


static func _build_catalogue() -> Array:
	var recipes: Array = [
		# --- Basics: the first minutes -------------------------------------
		_shapeless("planks_oak", "Basics", STATION_HAND, {BlockDB.OAK_LOG: 1}, BlockDB.PLANKS, 4),
		_shapeless("planks_pine", "Basics", STATION_HAND, {BlockDB.PINE_LOG: 1}, BlockDB.PLANKS, 4),
		_shapeless("planks_birch", "Basics", STATION_HAND, {BlockDB.BIRCH_LOG: 1}, BlockDB.PLANKS, 4),
		_shapeless("sticks", "Basics", STATION_HAND, {BlockDB.PLANKS: 2}, ItemDB.STICK, 4),
		_shapeless("crafting_table", "Basics", STATION_HAND, {BlockDB.PLANKS: 4}, BlockDB.CRAFTING_TABLE, 1),
		_shapeless("furnace", "Basics", STATION_TABLE, {BlockDB.COBBLESTONE: 8}, BlockDB.FURNACE, 1),
		# --- Building ------------------------------------------------------
		_shapeless("cobblestone", "Building", STATION_HAND, {BlockDB.STONE: 1}, BlockDB.COBBLESTONE, 1),
		_shapeless("stone_brick", "Building", STATION_TABLE, {BlockDB.COBBLESTONE: 4}, BlockDB.STONE_BRICK, 4),
		_shapeless("sandstone", "Building", STATION_TABLE, {BlockDB.SAND: 4}, BlockDB.SANDSTONE, 1),
		_shapeless("glass", "Building", STATION_HAND, {BlockDB.SAND: 2}, BlockDB.GLASS, 1),
		_shapeless("brick", "Building", STATION_TABLE, {BlockDB.CLAY: 4}, BlockDB.BRICK, 1),
		_shaped("chest", "Building", STATION_TABLE, ["PPP", "P P", "PPP"],
			{"P": BlockDB.PLANKS}, BlockDB.CHEST, 1),
		# M22 medieval vocabulary: every piece is craftable from mined materials,
		# so the showcase architecture is also a player-facing building set.
		_shapeless("timber_frame", "Building", STATION_TABLE,
			{BlockDB.PLANKS: 4, ItemDB.STICK: 2}, BlockDB.TIMBER_FRAME, 4),
		_shapeless("packed_path", "Building", STATION_HAND,
			{BlockDB.DIRT: 2, BlockDB.GRAVEL: 1}, BlockDB.PATH, 3),
		_shapeless("stair", "Building", STATION_TABLE,
			{BlockDB.PLANKS: 3, ItemDB.STICK: 1}, BlockDB.STAIR, 2),
		# M29 medieval palette: reachable from the same mined materials as the
		# earlier building set, with slate as a fired-stone roof family.
		_shapeless("plaster", "Building", STATION_TABLE,
			{BlockDB.SAND: 2, BlockDB.CLAY: 1}, BlockDB.PLASTER, 4),
		_shapeless("dark_timber", "Building", STATION_TABLE,
			{BlockDB.PLANKS: 2, ItemDB.COAL: 1}, BlockDB.DARK_TIMBER, 2),
		_shapeless("stone_wall", "Building", STATION_TABLE,
			{BlockDB.COBBLESTONE: 4}, BlockDB.STONE_WALL, 4),
		_shapeless("timber_brace", "Building", STATION_TABLE,
			{BlockDB.PLASTER: 1, BlockDB.DARK_TIMBER: 1}, BlockDB.TIMBER_BRACE, 2),
		_shapeless("slate_tile", "Building", STATION_TABLE,
			{BlockDB.STONE: 2, BlockDB.CLAY: 1}, BlockDB.SLATE_TILE, 4),
		_shapeless("slate_roof_stair", "Building", STATION_TABLE,
			{BlockDB.SLATE_TILE: 3, ItemDB.STICK: 1}, BlockDB.SLATE_STAIR, 2),
		_shapeless("slate_ramp", "Building", STATION_TABLE,
			{BlockDB.SLATE_TILE: 2}, BlockDB.SLATE_RAMP, 2),
		_shapeless("slate_slab", "Building", STATION_TABLE,
			{BlockDB.SLATE_TILE: 3}, BlockDB.SLATE_SLAB, 6),
		_shapeless("slate_ridge", "Building", STATION_TABLE,
			{BlockDB.SLATE_TILE: 2}, BlockDB.SLATE_RIDGE, 3),
		_shapeless("window", "Building", STATION_TABLE,
			{BlockDB.GLASS: 2, BlockDB.DARK_TIMBER: 1}, BlockDB.WINDOW, 2),
		_shapeless("shutter", "Building", STATION_TABLE,
			{BlockDB.DARK_TIMBER: 1}, BlockDB.SHUTTER, 2),
		_shapeless("chimney", "Building", STATION_TABLE,
			{BlockDB.STONE_WALL: 2, BlockDB.BRICK: 1}, BlockDB.CHIMNEY, 2),
		_shapeless("finial", "Building", STATION_TABLE,
			{BlockDB.DARK_TIMBER: 1, ItemDB.IRON_INGOT: 1}, BlockDB.FINIAL, 1),
		_shapeless("flower_box", "Building", STATION_TABLE,
			{BlockDB.PLANKS: 2, BlockDB.DIRT: 1}, BlockDB.FLOWER_BOX, 1),
		_shaped("fence", "Building", STATION_TABLE, ["P P", "PSP", "P P"],
			{"P": BlockDB.PLANKS, "S": ItemDB.STICK}, BlockDB.FENCE, 6),
		_shaped("door", "Building", STATION_TABLE, ["PP", "PP", "PP"],
			{"P": BlockDB.PLANKS}, BlockDB.DOOR, 1),
		_shapeless("barrel", "Building", STATION_TABLE,
			{BlockDB.PLANKS: 6, ItemDB.IRON_INGOT: 1}, BlockDB.BARREL, 1),
		_shaped("lantern", "Building", STATION_TABLE, [" I ", "ICI", " I "],
			{"I": ItemDB.IRON_INGOT, "C": ItemDB.COAL}, BlockDB.LANTERN, 1),
		# --- Tools ---------------------------------------------------------
		# Wooden: the first pickaxe, from planks and sticks.
		_shaped("wood_pickaxe", "Tools", STATION_TABLE, ["PPP", " S ", " S "],
			{"P": BlockDB.PLANKS, "S": ItemDB.STICK}, ItemDB.WOOD_PICKAXE, 1),
		_shaped("wood_axe", "Tools", STATION_TABLE, ["PP ", "PS ", " S "],
			{"P": BlockDB.PLANKS, "S": ItemDB.STICK}, ItemDB.WOOD_AXE, 1),
		_shaped("wood_shovel", "Tools", STATION_TABLE, [" P ", " S ", " S "],
			{"P": BlockDB.PLANKS, "S": ItemDB.STICK}, ItemDB.WOOD_SHOVEL, 1),
		_shaped("wood_sword", "Tools", STATION_TABLE, [" P ", " P ", " S "],
			{"P": BlockDB.PLANKS, "S": ItemDB.STICK}, ItemDB.WOOD_SWORD, 1),
		# Stone: the tier that mines iron.
		_shaped("stone_pickaxe", "Tools", STATION_TABLE, ["PPP", " S ", " S "],
			{"P": BlockDB.COBBLESTONE, "S": ItemDB.STICK}, ItemDB.STONE_PICKAXE, 1),
		_shaped("stone_axe", "Tools", STATION_TABLE, ["PP ", "PS ", " S "],
			{"P": BlockDB.COBBLESTONE, "S": ItemDB.STICK}, ItemDB.STONE_AXE, 1),
		_shaped("stone_shovel", "Tools", STATION_TABLE, [" P ", " S ", " S "],
			{"P": BlockDB.COBBLESTONE, "S": ItemDB.STICK}, ItemDB.STONE_SHOVEL, 1),
		_shaped("stone_sword", "Tools", STATION_TABLE, [" P ", " P ", " S "],
			{"P": BlockDB.COBBLESTONE, "S": ItemDB.STICK}, ItemDB.STONE_SWORD, 1),
		# Iron: needs the furnace and coal.
		_shaped("iron_pickaxe", "Tools", STATION_TABLE, ["PPP", " S ", " S "],
			{"P": ItemDB.IRON_INGOT, "S": ItemDB.STICK}, ItemDB.IRON_PICKAXE, 1),
		_shaped("iron_axe", "Tools", STATION_TABLE, ["PP ", "PS ", " S "],
			{"P": ItemDB.IRON_INGOT, "S": ItemDB.STICK}, ItemDB.IRON_AXE, 1),
		_shaped("iron_shovel", "Tools", STATION_TABLE, [" P ", " S ", " S "],
			{"P": ItemDB.IRON_INGOT, "S": ItemDB.STICK}, ItemDB.IRON_SHOVEL, 1),
		_shaped("iron_sword", "Tools", STATION_TABLE, [" P ", " P ", " S "],
			{"P": ItemDB.IRON_INGOT, "S": ItemDB.STICK}, ItemDB.IRON_SWORD, 1),
		# Diamond: the deepest tier.
		_shaped("diamond_pickaxe", "Tools", STATION_TABLE, ["PPP", " S ", " S "],
			{"P": ItemDB.DIAMOND, "S": ItemDB.STICK}, ItemDB.DIAMOND_PICKAXE, 1),
		_shaped("diamond_axe", "Tools", STATION_TABLE, ["PP ", "PS ", " S "],
			{"P": ItemDB.DIAMOND, "S": ItemDB.STICK}, ItemDB.DIAMOND_AXE, 1),
		_shaped("diamond_shovel", "Tools", STATION_TABLE, [" P ", " S ", " S "],
			{"P": ItemDB.DIAMOND, "S": ItemDB.STICK}, ItemDB.DIAMOND_SHOVEL, 1),
		_shaped("diamond_sword", "Tools", STATION_TABLE, [" P ", " P ", " S "],
			{"P": ItemDB.DIAMOND, "S": ItemDB.STICK}, ItemDB.DIAMOND_SWORD, 1),
		# --- Smelting: the furnace turns raw materials into better ones -----
		_smelting("iron_ingot", {ItemDB.IRON_LUMP: 1}, ItemDB.IRON_INGOT, 1, 8.0),
		_smelting("glass_from_sand", {BlockDB.SAND: 1}, BlockDB.GLASS, 1),
		_smelting("stone_from_cobble", {BlockDB.COBBLESTONE: 1}, BlockDB.STONE, 1),
		_smelting("brick_from_clay", {BlockDB.CLAY: 1}, BlockDB.BRICK, 1),
		_smelting("cooked_meat", {ItemDB.RAW_MEAT: 1}, ItemDB.COOKED_MEAT, 1, 5.0),
		_smelting("roof_tile", {BlockDB.CLAY: 2}, BlockDB.ROOF_TILE, 3, 4.0),
		# --- Food ----------------------------------------------------------
		_shapeless("bread", "Food", STATION_HAND, {ItemDB.WHEAT: 3}, ItemDB.BREAD, 1),
		_shapeless("bone_meal", "Food", STATION_HAND, {ItemDB.BONE: 1}, ItemDB.BONE_MEAL, 2),
		_shapeless("golden_apple", "Food", STATION_TABLE,
			{ItemDB.APPLE: 1, ItemDB.GOLD_LUMP: 8}, ItemDB.GOLDEN_APPLE, 1),
	]
	return recipes


static func _shapeless(id: String, category: String, station: String, inputs: Dictionary,
		output: int, output_count: int) -> Dictionary:
	return {
		"id": id, "category": category, "station": station,
		"inputs": inputs, "output": output, "output_count": output_count,
	}


static func _shaped(id: String, category: String, station: String, pattern: Array,
		key: Dictionary, output: int, output_count: int) -> Dictionary:
	return {
		"id": id, "category": category, "station": station,
		"pattern": pattern, "key": key, "output": output, "output_count": output_count,
	}


static func _smelting(id: String, inputs: Dictionary, output: int, output_count: int,
		time: float = 6.0) -> Dictionary:
	# `time` is the cook duration the placed-furnace interface uses; the recipe
	# list interface still consumes one unit of fuel per craft, so the two stay
	# consistent instead of contradicting each other.
	return {
		"id": id, "category": "Smelting", "station": STATION_FURNACE,
		"inputs": inputs, "fuel": {ItemDB.COAL: 1},
		"output": output, "output_count": output_count, "time": time,
	}


# --- catalogue access -----------------------------------------------------

## The fixed, ordered recipe list.  A deep copy is returned so callers cannot
## mutate the canonical data.
static func recipes() -> Array:
	return _recipes.duplicate(true)


static func recipe(id: String) -> Dictionary:
	var found: Variant = _by_id.get(id)
	return (found as Dictionary).duplicate(true) if found != null else {}


static func ids() -> Array:
	var result: Array = []
	for recipe_entry: Dictionary in _recipes:
		result.append(str(recipe_entry["id"]))
	return result


## Categories in catalogue order (the order the interface presents them in).
static func categories() -> Array:
	return _categories.duplicate()


static func recipes_in(category: String) -> Array:
	var result: Array = []
	for recipe_entry: Dictionary in _recipes:
		if str(recipe_entry["category"]) == category:
			result.append(recipe_entry.duplicate(true))
	return result


static func station_of(recipe_entry: Dictionary) -> String:
	return str(recipe_entry.get("station", STATION_HAND))


## The ingredients of a recipe.  Shaped recipes derive them from the pattern, so
## the declared ingredients and the shape can never disagree.
static func ingredients(recipe_entry: Dictionary) -> Dictionary:
	if not recipe_entry.has("pattern"):
		return (recipe_entry.get("inputs", {}) as Dictionary).duplicate()
	var counts := {}
	var key: Dictionary = recipe_entry.get("key", {})
	for row: String in (recipe_entry.get("pattern", []) as Array):
		for character in row.length():
			var symbol := row[character]
			if symbol == " ":
				continue
			var item_id := int(key.get(symbol, BlockDB.AIR))
			counts[item_id] = int(counts.get(item_id, 0)) + 1
	return counts


## The fuel a recipe burns, item id -> count (empty for anything but smelting).
static func fuel(recipe_entry: Dictionary) -> Dictionary:
	return (recipe_entry.get("fuel", {}) as Dictionary).duplicate()


## Human-readable recipe line, e.g. "3 Planks + 2 Stick → 1 Wooden Pickaxe".
static func label(recipe_entry: Dictionary) -> String:
	var parts: Array = []
	var inputs: Dictionary = ingredients(recipe_entry)
	var keys: Array = inputs.keys()
	keys.sort()
	for item_id in keys:
		parts.append("%d %s" % [int(inputs[item_id]), ItemDB.name_of(int(item_id))])
	var line := "%s \u2192 %d %s" % [
		" + ".join(parts),
		int(recipe_entry.get("output_count", 0)),
		ItemDB.name_of(int(recipe_entry.get("output", BlockDB.AIR))),
	]
	var extra: Array = []
	var fuel_items := fuel(recipe_entry)
	if not fuel_items.is_empty():
		var fuel_keys: Array = fuel_items.keys()
		fuel_keys.sort()
		for item_id in fuel_keys:
			extra.append("%d %s" % [int(fuel_items[item_id]), ItemDB.name_of(int(item_id))])
		extra.append("Furnace")
	elif station_of(recipe_entry) == STATION_TABLE:
		extra.append("Crafting Table")
	if not extra.is_empty():
		line += "  \u00b7  %s" % " + ".join(extra)
	return line


# --- queries --------------------------------------------------------------

## True when the station the player has is good enough for this recipe.
static func station_satisfied(recipe_entry: Dictionary, station: String) -> bool:
	var needed := int(STATION_RANK.get(station_of(recipe_entry), 0))
	var have := int(STATION_RANK.get(station, 0))
	return have >= needed


## True when the inventory holds the ingredients, the fuel (if any) and enough
## room for one craft's output.
static func can_craft(inventory: Inventory, recipe_entry: Dictionary,
		station: String = STATION_HAND) -> bool:
	return can_craft_times(inventory, recipe_entry, 1, station)


## True when the recipe can be crafted `count` times: ingredients and fuel at
## least `count` times over, and room for the whole output of the batch.
static func can_craft_times(inventory: Inventory, recipe_entry: Dictionary, count: int,
		station: String = STATION_HAND) -> bool:
	if count <= 0:
		return false
	return _failure(inventory, recipe_entry, count, station) == ""


## How many times the recipe can be crafted right now, limited by the ingredients
## and the fuel.  Output space is deliberately not part of this number: the
## interface asks `can_craft_times` for the batch it is about to perform.
static func craftable_count(inventory: Inventory, recipe_entry: Dictionary,
		station: String = STATION_HAND) -> int:
	if inventory == null or not station_satisfied(recipe_entry, station):
		return 0
	var limited := -1
	for item_id in _consumed(recipe_entry):
		var per_craft := int(_consumed(recipe_entry)[item_id])
		if per_craft <= 0:
			return 0
		var possible := inventory.count_of(int(item_id)) / per_craft
		if limited < 0 or possible < limited:
			limited = possible
	return maxi(0, limited)


## The recipes that can be crafted at the given station, in catalogue order.
## Each returned entry is a deep copy, so a caller cannot mutate the catalogue
## through it.
static func available_recipes(inventory: Inventory, station: String = STATION_HAND) -> Array:
	var ready: Array = []
	for recipe_entry: Dictionary in _recipes:
		if can_craft(inventory, recipe_entry, station):
			ready.append(recipe_entry.duplicate(true))
	return ready


## What is still missing for one craft: item id -> shortfall (ingredients and
## fuel).  Empty when nothing is missing.
static func missing(inventory: Inventory, recipe_entry: Dictionary,
		station: String = STATION_HAND) -> Dictionary:
	var shortfall := {}
	if inventory == null:
		return shortfall
	for item_id in _consumed(recipe_entry):
		var need := int(_consumed(recipe_entry)[item_id])
		var have := inventory.count_of(int(item_id))
		if have < need:
			shortfall[int(item_id)] = need - have
	return shortfall


# --- crafting -------------------------------------------------------------

## Result of a craft attempt.  Always a dictionary:
##     { "ok": bool, "reason": String, "output": item_id, "output_count": int,
##       "crafted": int }
## On failure nothing is consumed; `reason` explains why.
static func craft(inventory: Inventory, recipe_entry: Dictionary,
		station: String = STATION_HAND) -> Dictionary:
	return craft_many(inventory, recipe_entry, 1, station)


## Crafts `count` copies atomically: either all of them happen or none do.
static func craft_many(inventory: Inventory, recipe_entry: Dictionary, count: int,
		station: String = STATION_HAND) -> Dictionary:
	var output := int(recipe_entry.get("output", -1))
	var output_count := int(recipe_entry.get("output_count", 0))
	var failure := _failure(inventory, recipe_entry, count, station)
	if failure != "":
		return {"ok": false, "reason": failure, "output": output, "output_count": output_count,
			"crafted": 0}
	var consumed := _consumed(recipe_entry)
	for item_id in consumed:
		inventory.remove(int(item_id), int(consumed[item_id]) * count)
	var leftover := inventory.add(output, output_count * count)
	if leftover > 0:
		# Defensive: `_failure` already proved the output fits.
		return {"ok": false, "reason": "Inventory full", "output": output,
			"output_count": output_count, "crafted": 0}
	return {"ok": true, "reason": "", "output": output, "output_count": output_count,
		"crafted": count}


## Returns "" when the whole batch is possible, otherwise the reason it is not.
static func _failure(inventory: Inventory, recipe_entry: Dictionary, count: int,
		station: String) -> String:
	if count <= 0:
		return "Nothing to craft"
	var malformed := validate(recipe_entry)
	if malformed != "":
		return malformed
	if inventory == null:
		return "No inventory"
	if not station_satisfied(recipe_entry, station):
		return "%s needs a %s" % [ItemDB.name_of(int(recipe_entry["output"])),
			"furnace" if station_of(recipe_entry) == STATION_FURNACE else "crafting table"]
	var consumed := _consumed(recipe_entry)
	var missing_names: Array = []
	for item_id in consumed:
		var need := int(consumed[item_id]) * count
		if inventory.count_of(int(item_id)) < need:
			missing_names.append("%d more %s" % [
				need - inventory.count_of(int(item_id)), ItemDB.name_of(int(item_id))])
	if not missing_names.is_empty():
		return "Missing %s" % ", ".join(missing_names)
	if not _output_fits(inventory, consumed, count, int(recipe_entry["output"]),
			int(recipe_entry["output_count"]) * count):
		return "Inventory full \u2014 no room for %d %s" % [
			int(recipe_entry["output_count"]) * count, ItemDB.name_of(int(recipe_entry["output"]))]
	return ""


## Ingredients plus fuel, item id -> count per single craft.
static func _consumed(recipe_entry: Dictionary) -> Dictionary:
	var consumed: Dictionary = ingredients(recipe_entry)
	for item_id in fuel(recipe_entry):
		consumed[int(item_id)] = int(consumed.get(int(item_id), 0)) + int(fuel(recipe_entry)[item_id])
	return consumed


## True when `amount` of `output` fits once the consumed inputs have been removed
## for `count` crafts.  The check runs on a scratch copy of the stack counts, so
## consuming the inputs is allowed to free the room the output needs, and the
## per-slot stack cap is respected.
static func _output_fits(inventory: Inventory, consumed: Dictionary, count: int,
		output: int, amount: int) -> bool:
	if amount <= 0:
		return true
	var size: int = inventory.slots.size()
	var remaining: Array = inventory.counts.duplicate()
	for item_id in consumed:
		var to_remove := int(consumed[item_id]) * count
		for index in size:
			if to_remove <= 0:
				break
			if inventory.slots[index] == int(item_id) and int(remaining[index]) > 0:
				var take: int = mini(int(remaining[index]), to_remove)
				remaining[index] = int(remaining[index]) - take
				to_remove -= take
	# The output may top up an existing stack of the same item, or open a slot
	# that the consumption emptied (`remove()` clears those, exactly as a slot
	# with no items left is treated here).
	var capacity := maxi(1, ItemDB.max_stack(output))
	var left := amount
	for index in size:
		if left <= 0:
			break
		var held := int(remaining[index])
		if held > 0 and inventory.slots[index] == output:
			left -= mini(capacity - held, left)
		elif held <= 0:
			left -= mini(capacity, left)
	return left <= 0


# --- validation -----------------------------------------------------------

## Returns "" when the recipe is well formed, otherwise the reason it is not.
static func validate(recipe_entry: Dictionary) -> String:
	if recipe_entry.is_empty():
		return "Empty recipe"
	if str(recipe_entry.get("id", "")).is_empty():
		return "Recipe has no id"
	if str(recipe_entry.get("category", "")).is_empty():
		return "Recipe has no category"
	if not STATION_RANK.has(str(recipe_entry.get("station", ""))):
		return "Unknown station"
	var output := int(recipe_entry.get("output", -1))
	if output == BlockDB.AIR:
		return "Recipe output cannot be air"
	if not ItemDB.is_valid(output):
		return "Unknown output item"
	if int(recipe_entry.get("output_count", 0)) <= 0:
		return "Non-positive output count"
	if recipe_entry.has("fuel"):
		if station_of(recipe_entry) != STATION_FURNACE:
			return "Fuel on a recipe that does not smelt"
		if (recipe_entry.get("fuel", {}) as Dictionary).is_empty():
			return "Empty fuel"
		for item_id in (recipe_entry.get("fuel", {}) as Dictionary):
			if not ItemDB.is_valid(int(item_id)):
				return "Unknown fuel item"
			if int((recipe_entry.get("fuel", {}) as Dictionary)[item_id]) <= 0:
				return "Non-positive fuel count"
	var has_pattern := recipe_entry.has("pattern")
	var has_inputs := recipe_entry.has("inputs")
	if has_pattern == has_inputs:
		return "Recipe must declare exactly one of a pattern or inputs"
	if has_pattern:
		var pattern: Array = recipe_entry.get("pattern", [])
		if pattern.is_empty():
			return "Empty pattern"
		if pattern.size() > 3:
			return "Pattern taller than three rows"
		var key: Dictionary = recipe_entry.get("key", {})
		var cells := 0
		for row: String in pattern:
			if row.length() > 3:
				return "Pattern wider than three columns"
			for character in row.length():
				var symbol := row[character]
				if symbol == " ":
					continue
				cells += 1
				if not key.has(symbol):
					return "Pattern symbol '%s' has no key entry" % symbol
				if not ItemDB.is_valid(int(key[symbol])):
					return "Pattern key '%s' is not an item" % symbol
		if cells == 0:
			return "Pattern has no items"
		return ""
	for item_id in (recipe_entry.get("inputs", {}) as Dictionary):
		if not ItemDB.is_valid(int(item_id)):
			return "Unknown input item"
		if int((recipe_entry.get("inputs", {}) as Dictionary)[item_id]) <= 0:
			return "Non-positive input count"
	if (recipe_entry.get("inputs", {}) as Dictionary).is_empty():
		return "Recipe has no inputs"
	return ""


# --- shaped matching ------------------------------------------------------

## True when the given grid satisfies the recipe's shape.  `grid` is a list of
## rows of item ids (`BlockDB.AIR` = empty), at most 3x3; like Minecraft, the
## pattern may sit anywhere in the grid and empty rows and columns are trimmed
## before comparing, and a shaped pattern may be mirrored horizontally.  A
## shapeless recipe matches on the ingredient multiset, counting one item per
## occupied cell (use `match_shapeless_counts` when the grid can hold stacks).
static func match_grid(recipe_entry: Dictionary, grid: Array) -> bool:
	var ids := _grid_ids(grid)
	if not recipe_entry.has("pattern"):
		return _multiset(ids) == ingredients(recipe_entry)
	var pattern := _trim(_pattern_ids(recipe_entry))
	var placed := _trim(_ids_to_grid(ids, 3))
	if pattern == placed:
		return true
	# Minecraft-shaped recipes are mirrorable left-to-right (the axe pattern, for
	# example, works in both directions).
	return _mirror_rows(pattern) == placed


## Count-aware shapeless matching.  `counts` is item id -> quantity currently in
## the grid, so eight cobblestones stacked in one cell still satisfy the furnace
## recipe (the recipe is position-independent).  Zero/air entries are ignored.
static func match_shapeless_counts(recipe_entry: Dictionary, counts: Dictionary) -> bool:
	if recipe_entry.has("pattern"):
		return false
	var present := {}
	for item_id in counts:
		var value := int(counts[item_id])
		if value > 0 and int(item_id) != BlockDB.AIR:
			present[int(item_id)] = value
	return present == ingredients(recipe_entry)


static func _mirror_rows(rows: Array) -> Array:
	var mirrored: Array = []
	for row: Array in rows:
		var reverse: Array = []
		for index in range(row.size() - 1, -1, -1):
			reverse.append(int(row[index]))
		mirrored.append(reverse)
	return mirrored


static func _pattern_ids(recipe_entry: Dictionary) -> Array:
	var key: Dictionary = recipe_entry.get("key", {})
	var rows: Array = []
	for row: String in (recipe_entry.get("pattern", []) as Array):
		var values: Array = []
		for character in row.length():
			var symbol := row[character]
			values.append(BlockDB.AIR if symbol == " " else int(key.get(symbol, BlockDB.AIR)))
		rows.append(values)
	return rows


static func _ids_to_grid(ids: Array, width: int) -> Array:
	var rows: Array = []
	var row: Array = []
	for item_id in ids:
		row.append(int(item_id))
		if row.size() == width:
			rows.append(row)
			row = []
	if not row.is_empty():
		while row.size() < width:
			row.append(BlockDB.AIR)
		rows.append(row)
	return rows


static func _grid_ids(grid: Array) -> Array:
	var ids: Array = []
	for row: Variant in grid:
		if typeof(row) != TYPE_ARRAY:
			continue
		for item_id in (row as Array):
			ids.append(int(item_id))
	return ids


static func _multiset(ids: Array) -> Dictionary:
	var counts := {}
	for item_id in ids:
		var value := int(item_id)
		if value == BlockDB.AIR:
			continue
		counts[value] = int(counts.get(value, 0)) + 1
	return counts


## Removes empty rows and columns, so a pattern matches wherever it sits.
static func _trim(rows: Array) -> Array:
	var kept: Array = []
	for row: Array in rows:
		var any := false
		for value: int in row:
			if value != BlockDB.AIR:
				any = true
		kept.append(row.duplicate() if any else [])
	while not kept.is_empty():
		var empty := not _row_has_item(kept[0])
		if empty:
			kept.remove_at(0)
		else:
			break
	while not kept.is_empty():
		if not _row_has_item(kept[kept.size() - 1]):
			kept.remove_at(kept.size() - 1)
		else:
			break
	if kept.is_empty():
		return []
	var width := 0
	for row: Array in kept:
		width = maxi(width, row.size())
	var left := width
	var right := -1
	for row: Array in kept:
		for index in row.size():
			if int(row[index]) != BlockDB.AIR:
				left = mini(left, index)
				right = maxi(right, index)
	var trimmed: Array = []
	for row: Array in kept:
		var out: Array = []
		for index in range(left, right + 1):
			out.append(int(row[index]) if index < row.size() else BlockDB.AIR)
		trimmed.append(out)
	return trimmed


static func _row_has_item(row: Array) -> bool:
	for value: int in row:
		if value != BlockDB.AIR:
			return true
	return false


# --- stations -------------------------------------------------------------

## The station a block provides, or "" when it provides none.
static func station_of_block(block_id: int) -> String:
	match block_id:
		BlockDB.CRAFTING_TABLE:
			return STATION_TABLE
		BlockDB.FURNACE:
			return STATION_FURNACE
	return ""


## The best crafting station within `radius` of a world position: a furnace beats
## a crafting table beats nothing.  Only *loaded* blocks count, so the station
## follows the player's actual surroundings rather than the generator.
static func best_station(world: VoxelWorld, center: Vector3i, radius: int) -> String:
	if world == null:
		return STATION_HAND
	var best := STATION_HAND
	var best_rank := 0
	for dy in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if dx * dx + dy * dy + dz * dz > radius * radius:
					continue
				var position := center + Vector3i(dx, dy, dz)
				if not world.is_loaded(position):
					continue
				var station := station_of_block(world.get_block(position))
				if station.is_empty():
					continue
				var rank := int(STATION_RANK[station])
				if rank > best_rank:
					best_rank = rank
					best = station
	return best

class_name Crafting
extends RefCounted

## Deterministic crafting rules for the M17 Godot voxel game.
##
## This is the engine-independent data model: a fixed, ordered recipe list plus
## the queries the game and its crafting interface need.  It never touches the
## scene tree or the voxel world -- it only reads and mutates the player's
## `Inventory` model, which is itself node-free and serialisable.
##
## `craft()` is atomic: it validates the recipe, checks the ingredients and checks
## that the output fits the inventory *after* the inputs would be consumed -- all
## before touching the inventory -- so a craft that cannot complete leaves the
## inventory untouched.

## A recipe is a dictionary of the form:
##     { "inputs": { block_id: count, ... }, "output": block_id, "output_count": int }
## Every block id in a recipe refers to a real `BlockDB` definition.

static var _recipes: Array = []


static func _static_init() -> void:
	# A small, fixed, deterministic set built only from blocks the game can
	# actually obtain (mining drops plus the starter kit).  The order is stable
	# and is the order the interface presents them in.
	_recipes = [
		{"inputs": {BlockDB.OAK_LOG: 1}, "output": BlockDB.PLANKS, "output_count": 4},
		{"inputs": {BlockDB.PLANKS: 4}, "output": BlockDB.CRAFTING_TABLE, "output_count": 1},
		{"inputs": {BlockDB.STONE: 1}, "output": BlockDB.COBBLESTONE, "output_count": 1},
		{"inputs": {BlockDB.SAND: 2}, "output": BlockDB.GLASS, "output_count": 1},
		{"inputs": {BlockDB.CLAY: 4}, "output": BlockDB.BRICK, "output_count": 1},
	]


## The fixed, ordered recipe list.  A deep copy is returned so callers cannot
## mutate the canonical data.
static func recipes() -> Array:
	return _recipes.duplicate(true)


## True when the inventory holds at least the required amount of every input.
static func can_craft(inventory: Inventory, recipe: Dictionary) -> bool:
	if inventory == null or validate(recipe) != "":
		return false
	var inputs: Dictionary = recipe["inputs"]
	for block_id in inputs:
		if inventory.count_of(int(block_id)) < int(inputs[block_id]):
			return false
	return true


## The recipes the inventory can currently craft, in list order.  For the UI.
## Each returned entry is a deep copy, so a caller cannot mutate the canonical
## recipe list through it.
static func available_recipes(inventory: Inventory) -> Array:
	var ready: Array = []
	for recipe in _recipes:
		if can_craft(inventory, recipe):
			ready.append(recipe.duplicate(true))
	return ready


## Human-readable recipe line, e.g. "1 Oak Log -> 4 Planks".
static func label(recipe: Dictionary) -> String:
	var parts: Array = []
	var inputs: Dictionary = recipe.get("inputs", {})
	var keys: Array = inputs.keys()
	keys.sort()
	for block_id in keys:
		parts.append("%d %s" % [int(inputs[block_id]), BlockDB.name_of(int(block_id))])
	return "%s \u2192 %d %s" % [
		" + ".join(parts),
		int(recipe.get("output_count", 0)),
		BlockDB.name_of(int(recipe.get("output", BlockDB.AIR))),
	]


## The result of a craft attempt.  Always a dictionary:
##     { "ok": bool, "reason": String, "output": block_id, "output_count": int }
## On failure nothing is consumed; `reason` explains why.
static func craft(inventory: Inventory, recipe: Dictionary) -> Dictionary:
	var output := int(recipe.get("output", -1))
	var output_count := int(recipe.get("output_count", 0))
	var failure := validate(recipe)
	if failure == "" and inventory == null:
		failure = "No inventory"
	if failure == "" and not can_craft(inventory, recipe):
		failure = "Missing ingredients for %s" % label(recipe)
	if failure == "" and not _has_room_after(inventory, recipe, output, output_count):
		failure = "Inventory full — no room for %s" % BlockDB.name_of(output)
	if failure != "":
		return {"ok": false, "reason": failure, "output": output, "output_count": output_count}

	var inputs: Dictionary = recipe["inputs"]
	for block_id in inputs:
		inventory.remove(int(block_id), int(inputs[block_id]))
	var leftover := inventory.add(output, output_count)
	if leftover > 0:
		# Defensive: `_has_room_after` should already have guaranteed this.
		return {"ok": false, "reason": "Inventory full", "output": output, "output_count": output_count}
	return {"ok": true, "reason": "", "output": output, "output_count": output_count}


## Returns "" when the recipe is well formed, otherwise the reason it is not.
static func validate(recipe: Dictionary) -> String:
	if recipe.is_empty():
		return "Empty recipe"
	var output := int(recipe.get("output", -1))
	if output == BlockDB.AIR:
		return "Recipe output cannot be air"
	if output < 0 or output >= BlockDB.COUNT:
		return "Unknown output block"
	if int(recipe.get("output_count", 0)) <= 0:
		return "Non-positive output count"
	var inputs: Variant = recipe.get("inputs")
	if typeof(inputs) != TYPE_DICTIONARY or (inputs as Dictionary).is_empty():
		return "Recipe has no inputs"
	for block_id in (inputs as Dictionary):
		if int(block_id) < 0 or int(block_id) >= BlockDB.COUNT:
			return "Unknown input block"
		if int((inputs as Dictionary)[block_id]) <= 0:
			return "Non-positive input count"
	return ""


## True when `amount` of `block_id` fits once the recipe's inputs have been
## removed.  Capacity is judged against the post-consumption state, computed on a
## scratch copy of the slot counts (never the live inventory), so removing the
## inputs is allowed to free the room the output needs.  There is room when the
## output can merge into a stack that still holds items after consumption, or an
## empty slot remains.
static func _has_room_after(inventory: Inventory, recipe: Dictionary, block_id: int, amount: int) -> bool:
	if amount <= 0:
		return true
	var size: int = inventory.slots.size()
	var remaining: Array = inventory.counts.duplicate()
	var inputs: Dictionary = recipe["inputs"]
	for consumed_id in inputs:
		var to_remove := int(inputs[consumed_id])
		for index in size:
			if to_remove <= 0:
				break
			if inventory.slots[index] == int(consumed_id) and int(remaining[index]) > 0:
				var take: int = mini(int(remaining[index]), to_remove)
				remaining[index] = int(remaining[index]) - take
				to_remove -= take
	for index in size:
		if int(remaining[index]) > 0 and inventory.slots[index] == block_id:
			return true
		if int(remaining[index]) <= 0:
			return true
	return false

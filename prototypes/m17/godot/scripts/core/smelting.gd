class_name Smelting
extends RefCounted

## Smelting rules for the M17 Godot furnaces (M19).
##
## This is the engine-independent, pure-data part of furnace behaviour: which
## items burn as fuel, how long each fuel item lasts, and which item a given
## input smelts into.  The recipes themselves stay in `Crafting` (the single
## source of truth for the recipe catalogue), so a furnace never has a second
## recipe list: `recipe_for()` reads the catalogue's furnace recipes.
##
## Nothing here touches the scene tree, the world or any interface.

## Seconds one unit of a fuel item keeps a furnace burning.  One cook takes
## `cook_seconds()` (a property of the recipe), so coal lasts eight cooks.
const FUEL_SECONDS := {
	ItemDB.COAL: 48.0,
	BlockDB.OAK_LOG: 12.0,
	BlockDB.PINE_LOG: 12.0,
	BlockDB.PLANKS: 12.0,
	BlockDB.CRAFTING_TABLE: 12.0,
	ItemDB.STICK: 4.0,
}

## Most items take this long to smelt.  A recipe may override it with a `time`
## field; the catalogue does that for the slower metal recipes.
const DEFAULT_SECONDS := 6.0
## A recipe can never cook faster than this, so a malformed `time` cannot make a
## furnace free.
const MIN_SECONDS := 0.05


static func is_fuel(item_id: int) -> bool:
	return FUEL_SECONDS.has(item_id)


## Seconds of burn one unit of `item_id` provides (0 when it is not a fuel).
static func fuel_seconds(item_id: int) -> float:
	return float(FUEL_SECONDS.get(item_id, 0.0))


## The furnace recipe whose single input is `item_id`, or an empty dictionary.
static func recipe_for(input_item: int) -> Dictionary:
	if input_item == BlockDB.AIR or not ItemDB.is_valid(input_item):
		return {}
	for recipe: Dictionary in Crafting.recipes():
		if Crafting.station_of(recipe) != Crafting.STATION_FURNACE:
			continue
		var inputs: Dictionary = Crafting.ingredients(recipe)
		if inputs.size() != 1:
			continue
		if int(inputs.keys()[0]) == input_item and int(inputs[input_item]) == 1:
			return recipe
	return {}


## True when the item is a furnace input.
static func is_smeltable(item_id: int) -> bool:
	return not recipe_for(item_id).is_empty()


## The item a smeltable input produces (`BlockDB.AIR` when there is none).
static func output_for(input_item: int) -> int:
	var recipe := recipe_for(input_item)
	return BlockDB.AIR if recipe.is_empty() else int(recipe["output"])


## How many of the output one cook produces.
static func output_count_for(input_item: int) -> int:
	var recipe := recipe_for(input_item)
	return 0 if recipe.is_empty() else int(recipe.get("output_count", 1))


## Seconds of cooking the given recipe takes.
static func cook_seconds(recipe: Dictionary) -> float:
	return maxf(MIN_SECONDS, float(recipe.get("time", DEFAULT_SECONDS)))

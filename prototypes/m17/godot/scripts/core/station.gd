class_name Station
extends RefCounted

## A placed world-object station with its own persistent inventory (M19).
##
## A station is a block in the world (a crafting table or a furnace) plus a
## `StationInventory` whose slot layout comes from the block's kind.  This class
## owns the station *behaviour* that both interfaces and the game share:
##
##   * the crafting table's 3x3 grid, its recipe matching and the atomic craft
##     transaction (it reads the existing `Crafting` catalogue, so a recipe is
##     never redefined here);
##   * the furnace's input/fuel/output layout and its timed smelting step, driven
##     by the fuel and cook-time data in `Smelting`.
##
## Nothing here touches the scene tree or the world: the registry attaches a
## station to a world position, and the panel only reads and calls into it.

## Crafting table: nine grid slots (row-major) then the result slot.
const TABLE := "crafting_table"
## Furnace: input, fuel, output.
const FURNACE := "furnace"

const TABLE_GRID_SIZE := 9
const TABLE_GRID_SLOTS: int = TABLE_GRID_SIZE
const TABLE_OUTPUT_SLOT: int = TABLE_GRID_SIZE

const FURNACE_INPUT_SLOT := 0
const FURNACE_FUEL_SLOT := 1
const FURNACE_OUTPUT_SLOT := 2

const KIND_NAMES := {
	TABLE: "Crafting Table",
	FURNACE: "Furnace",
}
const KIND_LAYOUTS := {
	TABLE: [
		StationInventory.ROLE_GRID, StationInventory.ROLE_GRID, StationInventory.ROLE_GRID,
		StationInventory.ROLE_GRID, StationInventory.ROLE_GRID, StationInventory.ROLE_GRID,
		StationInventory.ROLE_GRID, StationInventory.ROLE_GRID, StationInventory.ROLE_GRID,
		StationInventory.ROLE_OUTPUT,
	],
	FURNACE: [
		StationInventory.ROLE_INPUT, StationInventory.ROLE_FUEL, StationInventory.ROLE_OUTPUT,
	],
}

var kind: String = TABLE
var inventory: StationInventory

## Furnace processing state (seconds).  Persisted so a furnace that was mid-cook
## resumes exactly where it left off after a save/load or chunk reload.
var burn_remaining := 0.0
var burn_total := 0.0
var cook_progress := 0.0
var cook_total := 0.0
## The input item the current cook started on, so changing the input resets the
## progress instead of finishing with the wrong item's time.
var cook_item := BlockDB.AIR


func _init(station_kind: String = TABLE) -> void:
	kind = station_kind
	inventory = StationInventory.new(_layout_for(kind))


static func _layout_for(station_kind: String) -> Array[String]:
	var roles: Array[String] = []
	for role: String in (KIND_LAYOUTS.get(station_kind, []) as Array):
		roles.append(role)
	return roles


## The station kind a block provides, or "" when it provides none.
static func kind_for_block(block_id: int) -> String:
	match block_id:
		BlockDB.CRAFTING_TABLE:
			return TABLE
		BlockDB.FURNACE:
			return FURNACE
	return ""


static func is_station_block(block_id: int) -> bool:
	return not kind_for_block(block_id).is_empty()


func label() -> String:
	return str(KIND_NAMES.get(kind, "Station"))


func is_furnace() -> bool:
	return kind == FURNACE


# =========================================================================
# Crafting table
# =========================================================================

## The grid as the 3x3 rows `Crafting.match_grid` expects.
func grid_rows() -> Array:
	var rows: Array = []
	for row in 3:
		var values: Array = []
		for column in 3:
			values.append(inventory.item_at(row * 3 + column))
		rows.append(values)
	return rows


## The recipe the grid currently satisfies, or an empty dictionary.  Hand recipes
## and crafting-table recipes are both craftable on a table (a table is at least
## as good as a hand), but furnace smelting recipes are not.
func matched_recipe() -> Dictionary:
	var grid := grid_rows()
	for recipe: Dictionary in Crafting.recipes():
		if Crafting.station_of(recipe) == Crafting.STATION_FURNACE:
			continue
		if Crafting.match_grid(recipe, grid):
			return recipe
	return {}


## The result the grid would produce right now, as
## `{ "recipe": Dictionary, "output": item_id, "count": int }`, or an empty
## dictionary when the grid matches nothing.  This is what the interface draws in
## the result slot.
func result_preview() -> Dictionary:
	var recipe := matched_recipe()
	if recipe.is_empty():
		return {}
	return {"recipe": recipe, "output": int(recipe["output"]), "count": int(recipe["output_count"])}


## Consumes one craft from the grid and puts the output in the result slot.
##
## Atomic: the result slot is checked first, so a craft that cannot store its
## output consumes nothing.  Like Minecraft, one item is taken from every
## occupied grid slot, which the grid match has already proven is exactly the
## recipe's ingredients.
##
## Returns `{ "ok": bool, "reason": String, "output": item_id, "count": int }`.
func craft_grid() -> Dictionary:
	var recipe := matched_recipe()
	if recipe.is_empty():
		return {"ok": false, "reason": "No matching recipe", "output": BlockDB.AIR, "count": 0}
	var output := int(recipe["output"])
	var amount := int(recipe["output_count"])
	if not _slot_fits(TABLE_OUTPUT_SLOT, output, amount):
		return {"ok": false, "reason": "Result slot is full", "output": output, "count": 0}
	for index in TABLE_GRID_SLOTS:
		if not inventory.is_empty(index):
			inventory.take(index, 1)
	inventory.insert(TABLE_OUTPUT_SLOT, {"item": output, "count": amount}, true)
	return {"ok": true, "reason": "", "output": output, "count": amount}


## Returns every item still in the grid (and the result slot) to `target`, an
## `Inventory`.  Whatever does not fit stays in the station, so closing an
## interface can never destroy an item; this is the documented "grid is
## persistent storage" policy.
func return_crafting_items(target: Inventory) -> int:
	var returned := 0
	if target == null:
		return 0
	for index in TABLE_GRID_SLOTS + 1:
		while not inventory.is_empty(index):
			var stack := inventory.take(index, 1)
			if target.add(int(stack["item"]), 1, int(stack.get("durability", -1))) > 0:
				# No room: put it back and stop trying this slot.
				inventory.insert(index, stack, index == TABLE_OUTPUT_SLOT)
				break
			returned += 1
	return returned


# =========================================================================
# Furnace
# =========================================================================

## True while the furnace is burning fuel or making progress, i.e. the visual
## state the interface should light up.
func is_active() -> bool:
	return burn_remaining > 0.0 or cook_progress > 0.0


## Progress of the current cook, 0..1 (0 when nothing is cooking).
func cook_ratio() -> float:
	if cook_total <= 0.0:
		return 0.0
	return clampf(cook_progress / cook_total, 0.0, 1.0)


## Remaining burn time as a fraction of one fuel unit, 0..1.
func fuel_ratio() -> float:
	if burn_total <= 0.0:
		return 0.0
	return clampf(burn_remaining / burn_total, 0.0, 1.0)


## Advances the furnace by `delta` seconds.  Returns true when anything changed,
## so the game can mark the station dirty and the interface can refresh.
##
##  * fuel only burns while there is something it can smelt and room for the
##    output, so fuel is never wasted on an idle furnace;
##  * a cook finishes atomically (input removed, output added in the same step);
##  * a full result slot pauses the cook instead of eating the input;
##  * a minimum of one step must pass on `delta <= 0`.
func step(delta: float) -> bool:
	if delta <= 0.0:
		return false
	var changed := false
	var input_item := inventory.item_at(FURNACE_INPUT_SLOT)
	var recipe := Smelting.recipe_for(input_item)
	var output := BlockDB.AIR if recipe.is_empty() else int(recipe["output"])
	var amount := 0 if recipe.is_empty() else int(recipe.get("output_count", 1))
	var can_cook := not recipe.is_empty() and _output_slot_fits(output, amount)
	if cook_item != input_item:
		if cook_progress != 0.0 or cook_total != 0.0:
			changed = true
		cook_item = input_item
		cook_progress = 0.0
		cook_total = 0.0
	if burn_remaining > 0.0:
		burn_remaining = maxf(0.0, burn_remaining - delta)
		changed = true
	if can_cook:
		if burn_remaining <= 0.0:
			if _light_fuel():
				changed = true
		if burn_remaining > 0.0:
			if cook_total <= 0.0:
				cook_total = Smelting.cook_seconds(recipe)
			cook_progress += delta
			changed = true
			if cook_progress >= cook_total:
				_finish_cook(recipe)
				cook_progress = 0.0
				cook_total = 0.0
	elif cook_progress > 0.0:
		# Nothing to smelt (or no room): the cook restarts when it can.
		cook_progress = 0.0
		cook_total = 0.0
		changed = true
	return changed


## True when a fuel item is in the fuel slot and at least one input is present.
func has_fuel() -> bool:
	return Smelting.is_fuel(inventory.item_at(FURNACE_FUEL_SLOT))


func _light_fuel() -> bool:
	var fuel_item := inventory.item_at(FURNACE_FUEL_SLOT)
	var seconds := Smelting.fuel_seconds(fuel_item)
	if seconds <= 0.0:
		return false
	inventory.take(FURNACE_FUEL_SLOT, 1)
	burn_remaining = seconds
	burn_total = seconds
	return true


func _finish_cook(recipe: Dictionary) -> void:
	inventory.remove_item(int(recipe["inputs"].keys()[0]), 1)
	inventory.insert(FURNACE_OUTPUT_SLOT,
		{"item": int(recipe["output"]), "count": int(recipe.get("output_count", 1))}, true)


func _output_slot_fits(output: int, amount: int) -> bool:
	return _slot_fits(FURNACE_OUTPUT_SLOT, output, amount)


## True when `amount` more of `output` fits in one slot.
func _slot_fits(index: int, output: int, amount: int) -> bool:
	if inventory.is_empty(index):
		return amount <= maxi(1, ItemDB.max_stack(output))
	if inventory.item_at(index) != output:
		return false
	return inventory.count_at(index) + amount <= maxi(1, ItemDB.max_stack(output))


# =========================================================================
# Persistence
# =========================================================================

func to_dictionary() -> Dictionary:
	return {
		"kind": kind,
		"inventory": inventory.to_dictionary(),
		"burn_remaining": burn_remaining,
		"burn_total": burn_total,
		"cook_progress": cook_progress,
		"cook_total": cook_total,
		"cook_item": cook_item,
	}


## Restores the station from a saved payload.  Atomic: the kind and the whole
## inventory are validated before anything is written, so a malformed or
## mismatched payload leaves the station untouched.
func from_dictionary(data: Dictionary) -> bool:
	if str(data.get("kind", "")) != kind:
		return false
	var probe := StationInventory.new(_layout_for(kind))
	if not probe.from_dictionary(data.get("inventory", {})):
		return false
	var burn := float(data.get("burn_remaining", 0.0))
	var burn_total_value := float(data.get("burn_total", 0.0))
	var progress := float(data.get("cook_progress", 0.0))
	var total := float(data.get("cook_total", 0.0))
	if burn < 0.0 or progress < 0.0 or total < 0.0:
		return false
	inventory = probe
	burn_remaining = burn
	burn_total = maxf(burn_total_value, 0.0)
	cook_progress = progress
	cook_total = maxf(total, 0.0)
	cook_item = int(data.get("cook_item", BlockDB.AIR))
	if not ItemDB.is_valid(cook_item):
		cook_item = BlockDB.AIR
	return true

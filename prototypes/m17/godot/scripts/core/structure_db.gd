class_name StructureDB
extends RefCounted

## Reusable, deterministic structure definitions (Phase D foundation).
##
## A structure is authored as ASCII layer maps so it can be read, edited and
## tested directly:
##
##     {"id": "hut", "name": "Abandoned Hut",
##      "biomes": [...],                 # allowed WorldGen biomes ([] = any land)
##      "min_floor_above_sea": 1,        # siting: how far above the sea the base must be
##      "max_slope": 4,                  # siting: allowed height spread over the footprint
##      "layers": [
##        {"dy": 0, "key": {"P": BlockDB.PLANKS}, "rows": ["PPPPP", ...]},
##      ]}
##
## In `rows`, row 0 is the -Z edge and each character is one +X step, so the
## footprint is `max(row length)` wide and `rows.size()` deep.  A `.` leaves the
## generated block alone (so a structure can sit on a hillside without carving),
## `_` forces air, and any other character must appear in that layer's `key`.
## `dy` is the height above the anchor, and may be negative (for things that are
## dug into the ground).
##
## Nothing here knows about the world or the seed: `WorldGen` owns the placement
## decision and the block writing.  These definitions are pure data, so they are
## shared by the generator, the tests and any future editor.

const NOTHING := "."
const AIR := "_"

static var _structures: Array = []
static var _by_id: Dictionary = {}
static var _max_extent := 0


static func _static_init() -> void:
	_structures = [
		_hut(),
		_campsite(),
		_watchtower(),
		_well(),
		_ore_outcrop(),
	]
	_by_id.clear()
	_max_extent = 0
	for definition: Dictionary in _structures:
		_by_id[str(definition["id"])] = definition
		var size := footprint(definition)
		_max_extent = maxi(_max_extent, maxi(size.x, size.z))


## The largest horizontal extent of any structure, so the generator can tell how
## far a structure can reach out of its anchor cell.
static func max_extent() -> int:
	return _max_extent


# --- catalogue ------------------------------------------------------------

## A small wooden home: planks and glass, a log roof, and a crafting table and
## furnace inside as the reward for finding it.
static func _hut() -> Dictionary:
	return {
		"id": "hut",
		"name": "Abandoned Hut",
		"biomes": [WorldGen.Biome.PLAINS, WorldGen.Biome.FOREST, WorldGen.Biome.SAVANNA,
			WorldGen.Biome.SNOW],
		"min_floor_above_sea": 1,
		"max_slope": 3,
		"layers": [
			{"dy": 0, "key": {"P": BlockDB.PLANKS, "T": BlockDB.CRAFTING_TABLE,
				"F": BlockDB.FURNACE},
				"rows": ["PPPPP", "PTPFP", "PPPPP", "PPPPP"]},
			{"dy": 1, "key": {"P": BlockDB.PLANKS, "G": BlockDB.GLASS},
				"rows": ["PGGGP", "P___P", "P___P", "PP_PP"]},
			{"dy": 2, "key": {"P": BlockDB.PLANKS, "G": BlockDB.GLASS},
				"rows": ["PGGGP", "P___P", "P___P", "PPPPP"]},
			{"dy": 3, "key": {"L": BlockDB.OAK_LOG},
				"rows": ["LLLLL", "LLLLL", "LLLLL", "LLLLL"]},
			{"dy": 4, "key": {"L": BlockDB.OAK_LOG},
				"rows": [".LLL.", ".LLL.", ".LLL.", ".LLL."]},
		],
	}


## A camp: a cobblestone platform, four log posts, and a crafting table next to a
## furnace so an early player gets both stations without a long trek.
static func _campsite() -> Dictionary:
	return {
		"id": "campsite",
		"name": "Campsite",
		"biomes": [WorldGen.Biome.PLAINS, WorldGen.Biome.FOREST, WorldGen.Biome.SAVANNA,
			WorldGen.Biome.MOUNTAIN],
		"min_floor_above_sea": 1,
		"max_slope": 2,
		"layers": [
			{"dy": 0, "key": {"C": BlockDB.COBBLESTONE},
				"rows": ["CCC", "CCC", "CCC"]},
			{"dy": 1, "key": {"O": BlockDB.OAK_LOG, "T": BlockDB.CRAFTING_TABLE,
				"F": BlockDB.FURNACE},
				"rows": ["OTO", "_F_", "O_O"]},
		],
	}


## A ruined watchtower: a broken stone-brick ring on a mossy base.  A landmark
## with a view and a few blocks' worth of stone bricks.
static func _watchtower() -> Dictionary:
	return {
		"id": "watchtower",
		"name": "Ruined Watchtower",
		"biomes": [WorldGen.Biome.PLAINS, WorldGen.Biome.SAVANNA, WorldGen.Biome.MOUNTAIN,
			WorldGen.Biome.SNOW, WorldGen.Biome.FOREST],
		"min_floor_above_sea": 2,
		"max_slope": 3,
		"layers": [
			{"dy": 0, "key": {"S": BlockDB.STONE_BRICK, "M": BlockDB.MOSSY_COBBLE},
				"rows": ["MMM", "MSM", "MMM"]},
			{"dy": 1, "key": {"S": BlockDB.STONE_BRICK, "M": BlockDB.MOSSY_COBBLE},
				"rows": ["S_S", "___", "S_S"]},
			{"dy": 2, "key": {"S": BlockDB.STONE_BRICK, "M": BlockDB.MOSSY_COBBLE},
				"rows": ["S_S", "___", "S_S"]},
			{"dy": 3, "key": {"S": BlockDB.STONE_BRICK, "M": BlockDB.MOSSY_COBBLE},
				"rows": ["M_S", "___", "__S"]},
			{"dy": 4, "key": {"S": BlockDB.STONE_BRICK, "M": BlockDB.MOSSY_COBBLE},
				"rows": ["M_M", "___", "M__"]},
		],
	}


## A desert well: a sandstone rim with a water source, a reliable drink stop.
static func _well() -> Dictionary:
	return {
		"id": "well",
		"name": "Desert Well",
		"biomes": [WorldGen.Biome.DESERT, WorldGen.Biome.BEACH, WorldGen.Biome.SAVANNA],
		"min_floor_above_sea": 1,
		"max_slope": 1,
		"layers": [
			{"dy": 0, "key": {"S": BlockDB.SANDSTONE, "W": BlockDB.WATER},
				"rows": ["SSS", "SWS", "SSS"]},
			{"dy": 1, "key": {"S": BlockDB.SANDSTONE},
				"rows": ["S_S", "___", "S_S"]},
		],
	}


## A surface ore outcrop: a cobble patch with coal and iron visible and a little
## more in the ground.  The reward is gated behind a pickaxe, so finding it early
## is a goal rather than a shortcut.
static func _ore_outcrop() -> Dictionary:
	return {
		"id": "ore_outcrop",
		"name": "Ore Outcrop",
		"biomes": [WorldGen.Biome.PLAINS, WorldGen.Biome.FOREST, WorldGen.Biome.SAVANNA,
			WorldGen.Biome.MOUNTAIN, WorldGen.Biome.SNOW],
		"min_floor_above_sea": 3,
		"max_slope": 2,
		"layers": [
			{"dy": 0, "key": {"C": BlockDB.COBBLESTONE, "K": BlockDB.COAL_ORE,
				"I": BlockDB.IRON_ORE},
				"rows": ["CKC", "CIC", "CKC"]},
			{"dy": -1, "key": {"C": BlockDB.COBBLESTONE, "K": BlockDB.COAL_ORE,
				"I": BlockDB.IRON_ORE},
				"rows": ["KCI", "CKI", "ICK"]},
			{"dy": -2, "key": {"C": BlockDB.COBBLESTONE, "K": BlockDB.COAL_ORE,
				"I": BlockDB.IRON_ORE},
				"rows": ["CIK", "CCI", "KCC"]},
		],
	}


# --- access ---------------------------------------------------------------

## Every definition, in catalogue order.  Deep copies so a caller cannot mutate
## the canonical data.
static func all() -> Array:
	return _structures.duplicate(true)


static func ids() -> Array:
	var result: Array = []
	for definition: Dictionary in _structures:
		result.append(str(definition["id"]))
	return result


static func definition(id: String) -> Dictionary:
	var found: Variant = _by_id.get(id)
	return (found as Dictionary).duplicate(true) if found != null else {}


static func has(id: String) -> bool:
	return _by_id.has(id)


# --- geometry -------------------------------------------------------------

## Width (x), height span (y, as the distance from the lowest to the highest
## layer) and depth (z) of a definition.
static func footprint(definition: Dictionary) -> Vector3i:
	var width := 0
	var depth := 0
	var lowest := 0
	var highest := 0
	for layer: Dictionary in definition.get("layers", []):
		var rows: Array = layer.get("rows", [])
		depth = maxi(depth, rows.size())
		for row: String in rows:
			width = maxi(width, row.length())
		lowest = mini(lowest, int(layer.get("dy", 0)))
		highest = maxi(highest, int(layer.get("dy", 0)))
	return Vector3i(width, highest - lowest + 1, depth)


## The block a layer's symbol places, or `BlockDB.NO_DROP` when the cell places
## nothing (`.`), and `BlockDB.AIR` when it forces air (`_`).
static func symbol_block(layer: Dictionary, symbol: String) -> int:
	if symbol == NOTHING:
		return BlockDB.NO_DROP
	if symbol == AIR:
		return BlockDB.AIR
	var key: Dictionary = layer.get("key", {})
	return int(key.get(symbol, BlockDB.NO_DROP))


## True when the structure may stand in this biome.
static func allows_biome(definition: Dictionary, biome: int) -> bool:
	var biomes: Array = definition.get("biomes", [])
	if biomes.is_empty():
		return true
	return biomes.has(biome)


# --- validation -----------------------------------------------------------

## Returns "" when the definition is well formed, otherwise why it is not.
static func validate(definition: Dictionary) -> String:
	if definition.is_empty():
		return "Empty structure"
	if str(definition.get("id", "")).is_empty():
		return "Structure has no id"
	if str(definition.get("name", "")).is_empty():
		return "Structure has no name"
	var layers: Variant = definition.get("layers")
	if typeof(layers) != TYPE_ARRAY or (layers as Array).is_empty():
		return "Structure has no layers"
	var width := 0
	var depth := 0
	var symbols := {}
	for layer: Dictionary in (layers as Array):
		var rows: Variant = layer.get("rows")
		if typeof(rows) != TYPE_ARRAY or (rows as Array).is_empty():
			return "A layer has no rows"
		if not (layer as Dictionary).has("dy"):
			return "A layer has no dy"
		var key: Dictionary = layer.get("key", {})
		if key.is_empty():
			return "A layer has no key"
		for symbol: String in key:
			if symbol.length() != 1:
				return "A key entry is not a single character: %s" % symbol
			if symbol == NOTHING or symbol == AIR:
				return "A key must not define the reserved symbol '%s'" % symbol
			if int(key[symbol]) < 0 or int(key[symbol]) >= BlockDB.COUNT:
				return "A key entry is not a real block: %s" % symbol
			symbols[symbol] = true
		var layer_depth := (rows as Array).size()
		depth = maxi(depth, layer_depth)
		for row: String in (rows as Array):
			width = maxi(width, row.length())
			for character in row.length():
				var symbol := row[character]
				if symbol == NOTHING:
					continue
				if symbol == AIR:
					continue
				if not symbols.has(symbol):
					return "Row symbol '%s' has no key entry" % symbol
	if width <= 0 or depth <= 0:
		return "Structure has no cells"
	if width > 8 or depth > 8:
		return "A structure footprint must fit in 8x8 (got %dx%d)" % [width, depth]
	if float(definition.get("min_floor_above_sea", 0.0)) < 0.0:
		return "min_floor_above_sea must not be negative"
	if int(definition.get("max_slope", 0)) < 0:
		return "max_slope must not be negative"
	for biome: Variant in definition.get("biomes", []):
		if int(biome) < 0 or int(biome) > WorldGen.Biome.MOUNTAIN:
			return "Unknown biome id %s" % biome
	return ""

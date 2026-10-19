extends RefCounted

## Structure definitions and their deterministic placement in the world.
##
## Structures are part of generation, so the contracts that matter are: the
## definitions are valid data, placement is a pure function of the seed and the
## region, siting is respected, and a structure that spans a chunk boundary is
## *complete* when both chunks are generated (no half buildings).
##
## Every helper here is bounded: the suite must stay fast, so the scans are small
## and the chunk loads are limited to the rows a structure actually occupies.

const SCAN := 8


func name() -> String:
	return "structures"


## Placements found in a bounded scan around the origin, computed once per run.
func _placements(seed: int, limit: int) -> Array:
	var generator := WorldGen.new(seed)
	var found: Array = []
	for region_z in range(-limit, limit + 1):
		for region_x in range(-limit, limit + 1):
			var placement := generator.structure_placement(Vector2i(region_x, region_z))
			if not placement.is_empty():
				found.append(placement)
	return found


func _origin_of(definition: Dictionary, placement: Dictionary) -> Vector2i:
	var size := StructureDB.footprint(definition)
	return Vector2i(int(placement["x"]) - (size.x - 1) / 2, int(placement["z"]) - (size.z - 1) / 2)


func _test_definitions(h: TestHarness) -> void:
	var definitions: Array = StructureDB.all()
	h.greater(float(definitions.size()), 3.0, "the catalogue has several structures (%d)" % definitions.size())
	h.check(StructureDB.all() == definitions, "all() is deterministic across calls")
	var ids := {}
	var invalid: Array[String] = []
	for definition: Dictionary in definitions:
		ids[str(definition["id"])] = true
		var reason := StructureDB.validate(definition)
		if not reason.is_empty():
			invalid.append("%s: %s" % [definition["id"], reason])
	h.eq(invalid, [], "every definition is valid")
	h.eq(ids.size(), definitions.size(), "structure ids are unique")
	h.check(StructureDB.max_extent() * 2 < WorldGen.STRUCTURE_REGION,
		"a footprint can never reach out of its own region")
	h.check(StructureDB.has("hut"), "a definition can be looked up by id")
	h.check((StructureDB.definition("nope") as Dictionary).is_empty(), "an unknown id resolves to nothing")

	# M22 architecture vocabulary: both new definitions are valid, fit the raised
	# footprint limit, and use the shared blocks rather than bespoke ids.
	for id: String in ["timber_cottage", "market_stall"]:
		var definition := StructureDB.definition(id)
		h.eq(StructureDB.validate(definition), "", "%s is a valid definition" % id)
	var cottage := StructureDB.footprint(StructureDB.definition("timber_cottage"))
	h.eq(cottage, Vector3i(9, 9, 7), "the cottage footprint is 9x7 with nine layers (including the chimney)")
	var stall := StructureDB.footprint(StructureDB.definition("market_stall"))
	h.eq(stall, Vector3i(5, 5, 3), "the market stall footprint is 5x3 with five layers")
	h.check(str(StructureDB.definition("timber_cottage")["name"]) == "Timber Cottage",
		"the cottage has a readable name")
	# Stamping the shared definition at runtime produces the same blocks as the
	# generator's cross-chunk writer.
	var stamped_world := VoxelWorld.new(17017)
	var placed := StructureDB.stamp(stamped_world, "timber_cottage", Vector2i(8, 8), 70)
	h.greater(float(placed), 200.0, "the cottage stamps a complete building")
	h.eq(stamped_world.get_block(Vector3i(8, 71, 11)), BlockDB.DOOR,
		"the stamped cottage has its door on the south face")
	h.eq(stamped_world.get_block(Vector3i(6, 74, 6)), BlockDB.ROOF_TILE,
		"the stamped cottage has its tiled roof")

	# Every kind must be *placeable*: a non-empty biome list of land biomes and a
	# reachable floor height.
	var unplaceable: Array[String] = []
	for definition: Dictionary in definitions:
		if (definition.get("biomes", []) as Array).is_empty():
			unplaceable.append("%s: any biome" % definition["id"])
		if int(definition.get("min_floor_above_sea", 0)) > 40:
			unplaceable.append("%s: floor too high" % definition["id"])
	h.eq(unplaceable, [], "every kind's siting constraints are satisfiable")

	# Footprints are measured from the layer maps.
	var size := StructureDB.footprint(StructureDB.definition("hut"))
	h.eq(size, Vector3i(5, 5, 4), "the hut is 5x5 layers x4 blocks deep")
	h.eq(StructureDB.footprint(StructureDB.definition("ore_outcrop")), Vector3i(3, 3, 3),
		"the ore outcrop spans three layers (dy -2..0)")

	# Bad definitions are rejected.
	var rejects := [
		[{}, "an empty definition"],
		[{"id": "x", "name": "X", "layers": []}, "no layers"],
		[{"id": "x", "name": "X", "layers": [{"dy": 0, "key": {}, "rows": ["S"]}]}, "an empty key"],
		[{"id": "x", "name": "X", "layers": [{"dy": 0, "key": {"S": BlockDB.STONE}, "rows": []}]}, "a layer with no rows"],
		[{"id": "x", "name": "X", "layers": [{"dy": 0, "key": {"S": BlockDB.STONE}, "rows": ["SSSSSSSSSSSSS"]}]},
			"a footprint wider than the limit"],
		[{"id": "x", "name": "X", "layers": [{"dy": 0, "key": {"S": BlockDB.STONE}, "rows": ["Z"]}]},
			"a row symbol with no key entry"],
		[{"id": "x", "name": "X", "layers": [{"key": {"S": BlockDB.STONE}, "rows": ["S"]}]},
			"a layer with no dy"],
		[{"id": "x", "name": "X", "layers": [{"dy": 0, "key": {"S": 999}, "rows": ["S"]}]},
			"a key entry that is not a block"],
		[{"id": "x", "name": "X", "biomes": [99],
			"layers": [{"dy": 0, "key": {"S": BlockDB.STONE}, "rows": ["S"]}]}, "an unknown biome"],
		[{"id": "x", "name": "X", "max_slope": -1,
			"layers": [{"dy": 0, "key": {"S": BlockDB.STONE}, "rows": ["S"]}]}, "a negative slope limit"],
		[{"id": "x", "name": "X", "min_floor_above_sea": -2,
			"layers": [{"dy": 0, "key": {"S": BlockDB.STONE}, "rows": ["S"]}]}, "a negative floor height"],
	]
	for case: Array in rejects:
		h.check(StructureDB.validate(case[0]) != "", "a definition with %s is rejected" % case[1])

	# The reserved layer symbols behave as documented.
	var layer := {"key": {"S": BlockDB.STONE}, "rows": ["S"]}
	h.eq(StructureDB.symbol_block(layer, "."), BlockDB.NO_DROP, "a dot leaves the world alone")
	h.eq(StructureDB.symbol_block(layer, "_"), BlockDB.AIR, "an underscore forces air")
	h.eq(StructureDB.symbol_block(layer, "S"), BlockDB.STONE, "a key symbol places its block")
	h.eq(StructureDB.symbol_block(layer, "Z"), BlockDB.NO_DROP, "an unknown symbol places nothing")


func _test_placement_is_deterministic(h: TestHarness) -> void:
	var first := _placements(17017, SCAN)
	h.greater(float(first.size()), 5.0, "a bounded scan finds several structures (%d)" % first.size())
	var again := _placements(17017, 3)
	h.eq(_placements(17017, 3), again, "the same seed and scan give identical placements")
	var other := _placements(4242, 3)
	h.check(other != again, "a different seed places different structures")

	# The same region always answers the same, whatever else was queried first.
	var generator := WorldGen.new(17017)
	var region := Vector2i(1, -2)
	var before := generator.structure_placement(region)
	generator.structure_placement(Vector2i(-40, 33))
	h.eq(generator.structure_placement(region), before, "a region's placement does not depend on query order")

	# Region maths must be correct for negative coordinates too.
	h.eq(WorldGen.structure_region_of(0), 0, "the origin is in region zero")
	h.eq(WorldGen.structure_region_of(WorldGen.STRUCTURE_REGION - 1), 0, "the last block is still region zero")
	h.eq(WorldGen.structure_region_of(WorldGen.STRUCTURE_REGION), 1, "the next block starts region one")
	h.eq(WorldGen.structure_region_of(-1), -1, "the block before the origin is region -1")
	h.eq(WorldGen.structure_region_of(-WorldGen.STRUCTURE_REGION - 1), -2, "negative regions use floor semantics")


func _test_siting(h: TestHarness) -> void:
	var placements := _placements(17017, SCAN)
	var generator := WorldGen.new(17017)
	var bad_siting: Array[String] = []
	var kinds := {}
	for placement: Dictionary in placements:
		var definition := StructureDB.definition(str(placement["id"]))
		kinds[str(placement["id"])] = true
		var size := StructureDB.footprint(definition)
		var origin := _origin_of(definition, placement)
		var lowest := WorldGen.WORLD_HEIGHT
		var highest := 0
		for local_z in size.z:
			for local_x in size.x:
				var height := generator.height_at(origin.x + local_x, origin.y + local_z)
				lowest = mini(lowest, height)
				highest = maxi(highest, height)
		if not StructureDB.allows_biome(definition, generator.biome_at(origin.x, origin.y)):
			bad_siting.append("%s in the wrong biome" % placement["id"])
		if highest - lowest > int(definition["max_slope"]):
			bad_siting.append("%s on too steep a slope" % placement["id"])
		if int(placement["base_y"]) - 1 < WorldGen.SEA_LEVEL + int(definition["min_floor_above_sea"]):
			bad_siting.append("%s below sea level" % placement["id"])
		if int(placement["base_y"]) != highest + 1:
			bad_siting.append("%s does not sit on the highest footprint column" % placement["id"])
	h.eq(bad_siting, [], "every placement respects its siting rules")
	h.greater(float(kinds.size()), 2.0, "a bounded scan finds several kinds (%s)" % ", ".join(kinds.keys()))
	h.check(kinds.has("timber_cottage"), "the timber cottage appears in normal generation")
	h.check(kinds.has("market_stall"), "the market stall appears in normal generation")


## The important one: a structure that straddles a chunk boundary is complete when
## both chunks exist, because each chunk writes its own part.  Only the chunk rows
## a structure actually occupies are generated, so the check stays cheap.
func _test_structures_are_complete_across_chunks(h: TestHarness) -> void:
	var generator := WorldGen.new(17017)
	var placements := _placements(17017, SCAN)
	h.greater(float(placements.size()), 2.0, "found structures to check")
	var checked := 0
	var straddling := 0
	var mismatches: Array[String] = []
	var world := VoxelWorld.new(17017)
	for placement: Dictionary in placements:
		if checked >= 6:
			break
		var definition := StructureDB.definition(str(placement["id"]))
		var size := StructureDB.footprint(definition)
		var origin := _origin_of(definition, placement)
		var base_y := int(placement["base_y"])
		var lowest_y := base_y
		var highest_y := base_y
		for layer: Dictionary in definition["layers"]:
			lowest_y = mini(lowest_y, base_y + int(layer["dy"]))
			highest_y = maxi(highest_y, base_y + int(layer["dy"]))
		# One chunk column of margin in x/z (so a straddling structure is written
		# by both neighbours) and only the y rows the structure occupies.
		for chunk_y in range(VoxelWorld.world_to_chunk(Vector3i(0, lowest_y, 0)).y,
				VoxelWorld.world_to_chunk(Vector3i(0, highest_y, 0)).y + 1):
			for chunk_z in range(VoxelWorld.world_to_chunk(Vector3i(0, 0, origin.y)).z - 1,
					VoxelWorld.world_to_chunk(Vector3i(0, 0, origin.y + size.z)).z + 2):
				for chunk_x in range(VoxelWorld.world_to_chunk(Vector3i(origin.x, 0, 0)).x - 1,
						VoxelWorld.world_to_chunk(Vector3i(origin.x + size.x, 0, 0)).x + 2):
					world.ensure_chunk(Vector3i(chunk_x, chunk_y, chunk_z))
		for layer: Dictionary in definition["layers"]:
			var world_y := base_y + int(layer["dy"])
			var rows: Array = layer["rows"]
			for row_index in rows.size():
				var row := str(rows[row_index])
				for column in row.length():
					var expected := StructureDB.symbol_block(layer, row[column])
					if expected == BlockDB.NO_DROP:
						continue
					var cell := Vector3i(origin.x + column, world_y, origin.y + row_index)
					var local := VoxelWorld.world_to_local(cell)
					if local.x == 0 or local.x == 15 or local.z == 0 or local.z == 15:
						straddling += 1
					var actual := world.get_block(cell)
					if actual != expected:
						mismatches.append("%s at %s: expected %s, got %s" % [placement["id"], str(cell),
							BlockDB.name_of(expected), BlockDB.name_of(actual)])
		checked += 1
	h.greater(float(checked), 0.0, "checked %d placements" % checked)
	h.eq(mismatches.slice(0, 4), [], "every structure block is present where the definition puts it")
	h.greater(float(straddling), 0.0,
		"at least one checked structure crosses a chunk boundary (%d blocks on a border)" % straddling)


## The ore outcrop digs below the surface: it must never open the bottom of the
## world, and the well must actually place water.
func _test_digs_and_water(h: TestHarness) -> void:
	var placements := _placements(17017, SCAN)
	var outcrop := {}
	for placement: Dictionary in placements:
		if str(placement["id"]) == "ore_outcrop":
			outcrop = placement
			break
	if outcrop.is_empty():
		h.check(false, "an ore outcrop exists in the scan")
		return
	var definition := StructureDB.definition("ore_outcrop")
	var origin := _origin_of(definition, outcrop)
	var world := VoxelWorld.new(17017)
	var centre := Vector3i(int(outcrop["x"]), 0, int(outcrop["z"]))
	for chunk_y in range(WorldGen.CHUNKS_Y):
		world.ensure_chunk(Vector3i(VoxelWorld.world_to_chunk(centre).x, chunk_y, VoxelWorld.world_to_chunk(centre).z))
	h.eq(world.get_block(Vector3i(centre.x, 0, centre.z)), BlockDB.BEDROCK,
		"the bottom of the world survives a structure")
	var ore_cells := 0
	for layer: Dictionary in definition["layers"]:
		var base_y := int(outcrop["base_y"]) + int(layer["dy"])
		var rows: Array = layer["rows"]
		for row_index in rows.size():
			var row := str(rows[row_index])
			for column in row.length():
				var expected := StructureDB.symbol_block(layer, row[column])
				if expected == BlockDB.COAL_ORE or expected == BlockDB.IRON_ORE:
					if world.get_block(Vector3i(origin.x + column, base_y, origin.y + row_index)) == expected:
						ore_cells += 1
	h.greater(float(ore_cells), 5.0, "the outcrop presents real ore blocks (%d)" % ore_cells)

	var well := StructureDB.definition("well")
	var has_water := false
	for layer: Dictionary in well["layers"]:
		for row: String in layer["rows"]:
			if row.contains("W"):
				has_water = true
	h.check(has_water, "the well definition places a water source")


func run(h: TestHarness) -> void:
	_test_definitions(h)
	_test_placement_is_deterministic(h)
	_test_siting(h)
	_test_structures_are_complete_across_chunks(h)
	_test_digs_and_water(h)
	h.finish()

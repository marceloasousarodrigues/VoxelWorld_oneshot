extends RefCounted

## M37 (generator v8): larger irregular forest openings, compact crowns,
## preserved v7 treeline, deterministic placement and chunk-boundary safety.

const PINNED_LEGACY_HASH := 3214517825889907206
const PINNED_M30_HASH := 5947596836865492245
const PINNED_M31_HASH := 8397584315617538769
const PINNED_M32_HASH := 8802792587028581708
const PINNED_M33_HASH := 2164503133686526591
const PINNED_M34_HASH := 5133898688464144157
const PINNED_M35_HASH := 9184026728463986701
const PINNED_M36_HASH := 5732396842800747576
const PINNED_M37_HASH := 6693088695751418916
const SEA := WorldGen.SEA_LEVEL
const SAMPLE_RADIUS := 192
const DENSE_BOX := Rect2i(60, -104, 64, 64)
const CANOPY_BOX := Rect2i(192, 256, 64, 64)


func name() -> String:
	return "M37 forest composition"


func _region_hash(version: int) -> int:
	var world := VoxelWorld.new(17017, version)
	for chunk_z in range(-2, 3):
		for chunk_x in range(-2, 3):
			for chunk_y in range(0, 6):
				world.ensure_chunk(Vector3i(chunk_x, chunk_y, chunk_z))
	return world.fingerprint()


func _is_tree(type: int) -> bool:
	return type != WorldGen.TreeType.NONE


func _is_broadleaf(type: int) -> bool:
	return type == WorldGen.TreeType.OAK or type == WorldGen.TreeType.BIRCH \
		or type == WorldGen.TreeType.BLOSSOM


func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var index := clampi(int(round(fraction * float(values.size() - 1))), 0, values.size() - 1)
	return values[index]


func _crown_stats(generator: WorldGen, box: Rect2i) -> Dictionary:
	var trees: Array[Dictionary] = []
	for z in range(box.position.y - 10, box.end.y + 10):
		for x in range(box.position.x - 10, box.end.x + 10):
			var tree := generator.tree_at(x, z)
			var type := int(tree["type"])
			if not _is_tree(type):
				continue
			var radius := 5
			if type == WorldGen.TreeType.CACTUS:
				continue
			if _is_broadleaf(type):
				radius = int(tree.get("canopy", 3)) + 2
			if x + radius < box.position.x or x - radius >= box.end.x \
					or z + radius < box.position.y or z - radius >= box.end.y:
				continue
			trees.append({"x": x, "z": z, "r": radius})
	var counts := {}
	for entry: Dictionary in trees:
		var r := int(entry["r"])
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dz * dz > r * r:
					continue
				var key := Vector2i(int(entry["x"]) + dx, int(entry["z"]) + dz)
				counts[key] = int(counts.get(key, 0)) + 1
	var columns := 0
	var open := 0
	var multi := 0
	var triple := 0
	for z in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			if generator.biome_at(x, z) != WorldGen.Biome.FOREST:
				continue
			columns += 1
			var count := int(counts.get(Vector2i(x, z), 0))
			if count == 0:
				open += 1
			if count >= 2:
				multi += 1
			if count >= 3:
				triple += 1
	var open_cells := {}
	for z in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			if generator.biome_at(x, z) != WorldGen.Biome.FOREST:
				continue
			var cell := Vector2i(x, z)
			if int(counts.get(cell, 0)) == 0:
				open_cells[cell] = true
	var seen := {}
	var largest_open := 0
	for cell: Vector2i in open_cells:
		if seen.has(cell):
			continue
		var stack: Array[Vector2i] = [cell]
		seen[cell] = true
		var count := 0
		while not stack.is_empty():
			var current: Vector2i = stack.pop_back()
			count += 1
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var neighbour: Vector2i = current + offset
				if open_cells.has(neighbour) and not seen.has(neighbour):
					seen[neighbour] = true
					stack.append(neighbour)
		largest_open = maxi(largest_open, count)
	return {
		"columns": columns,
		"open": float(open) / maxf(1.0, float(columns)),
		"multi": float(multi) / maxf(1.0, float(columns)),
		"triple": float(triple) / maxf(1.0, float(columns)),
		"covered": float(columns - open) / maxf(1.0, float(columns)),
		"largest_open": largest_open,
	}


func _coverage(generator: WorldGen) -> Dictionary:
	var forest := 0
	var trees := 0
	var dense_columns := 0
	var dense_trees := 0
	var open_low := 0
	for z in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
		for x in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
			if generator.biome_at(x, z) != WorldGen.Biome.FOREST:
				continue
			forest += 1
			var is_tree := _is_tree(int(generator.tree_at(x, z)["type"]))
			if is_tree:
				trees += 1
			var patch := generator._forest_patches.get_noise_2d(x, z)
			if patch > WorldGen.M34_GROVE_PATCH:
				dense_columns += 1
				dense_trees += 1 if is_tree else 0
			elif generator.height_at(x, z) <= SEA + 8:
				open_low += 1 if is_tree else 0
	return {
		"forest": forest,
		"trees": trees,
		"coverage": float(trees) / maxf(1.0, float(forest)),
		"dense_columns": dense_columns,
		"dense_trees": dense_trees,
		"open_low": open_low,
	}


func _treeline(generator: WorldGen) -> Dictionary:
	var trees := 0
	var max_root := -1
	var max_top := -1
	var above_root := 0
	var above_top := 0
	for z in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
		for x in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
			var tree := generator.tree_at(x, z)
			if not _is_tree(int(tree["type"])):
				continue
			trees += 1
			var root := int(tree["base"]) - 1
			var top := generator._tree_top_y(tree)
			max_root = maxi(max_root, root)
			max_top = maxi(max_top, top)
			if root > WorldGen.M35_TREELINE_LIMIT:
				above_root += 1
			if top > WorldGen.M36_CANOPY_CEILING:
				above_top += 1
	return {"trees": trees, "max_root": max_root, "max_top": max_top,
		"above_root": above_root, "above_top": above_top}


func run(h: TestHarness) -> void:
	h.section("M37 generator versions")
	h.eq(WorldGen.M36_VERSION, 7, "the v7 treeline pass remains version 7")
	h.eq(WorldGen.M37_VERSION, 8, "the forest composition pass is version 8")
	h.eq(WorldGen.CURRENT_VERSION, 8, "new worlds use the M37 generator")
	for version in range(0, WorldGen.CURRENT_VERSION + 1):
		h.check(WorldGen.is_supported_version(version), "version %d remains loadable" % version)
	h.check(not WorldGen.is_supported_version(WorldGen.CURRENT_VERSION + 1),
		"a future version is rejected")
	h.eq(_region_hash(0), PINNED_LEGACY_HASH, "version 0 remains pinned")
	h.eq(_region_hash(1), PINNED_M30_HASH, "version 1 remains pinned")
	h.eq(_region_hash(2), PINNED_M31_HASH, "version 2 remains pinned")
	h.eq(_region_hash(3), PINNED_M32_HASH, "version 3 remains pinned")
	h.eq(_region_hash(4), PINNED_M33_HASH, "version 4 remains pinned")
	h.eq(_region_hash(5), PINNED_M34_HASH, "version 5 remains pinned")
	h.eq(_region_hash(6), PINNED_M35_HASH, "version 6 remains pinned")
	h.eq(_region_hash(7), PINNED_M36_HASH, "version 7 remains pinned")
	var v8_a := _region_hash(8)
	var v8_b := _region_hash(8)
	h.eq(v8_a, v8_b, "version 8 generation is deterministic")
	h.eq(v8_a, PINNED_M37_HASH, "version 8 output is pinned")
	h.check(v8_a != PINNED_M36_HASH, "version 8 differs from version 7")

	var v7 := WorldGen.new(17017, 7)
	var v8 := WorldGen.new(17017, 8)
	var height_mismatch := 0
	var biome_mismatch := 0
	for z in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1, 4):
		for x in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1, 4):
			if v7.height_at(x, z) != v8.height_at(x, z):
				height_mismatch += 1
			if v7.biome_at(x, z) != v8.biome_at(x, z):
				biome_mismatch += 1
	h.eq(height_mismatch, 0, "v8 heights equal v7")
	h.eq(biome_mismatch, 0, "v8 biomes equal v7")

	h.section("M37 forest composition")
	var v7_coverage := _coverage(v7)
	var v8_coverage := _coverage(v8)
	h.greater(float(v8_coverage["forest"]), 10000.0, "the v8 forest sample is large")
	h.greater(v8_coverage["coverage"], 0.018, "v8 keeps at least 1.8%% global forest")
	h.less(v8_coverage["coverage"], 0.06, "v8 is not a solid forest")
	h.less(v8_coverage["coverage"], v7_coverage["coverage"], "v8 is more open than v7")
	h.greater(float(v8_coverage["dense_trees"]), 50.0, "v8 keeps dense-grove trees")
	h.less(v8_coverage["dense_trees"], v7_coverage["dense_trees"], "v8 opens dense groves")
	h.less(v8_coverage["open_low"], v7_coverage["open_low"], "v8 also opens open woodland")

	var v7_dense := _crown_stats(v7, DENSE_BOX)
	var v8_dense := _crown_stats(v8, DENSE_BOX)
	h.greater(v8_dense["open"], v7_dense["open"], "v8 opens the dense-grove box")
	h.less(v8_dense["multi"], v7_dense["multi"], "v8 reduces 2+ crown overlap in dense groves")
	h.less(v8_dense["triple"], v7_dense["triple"], "v8 reduces 3+ crown overlap in dense groves")
	h.greater(float(v8_dense["largest_open"]), float(v7_dense["largest_open"]),
		"v8 creates a larger connected opening in dense groves")
	h.greater(v8_dense["open"], 0.45, "v8 dense-grove box is at least 45%% open")
	h.greater(float(v8_dense["largest_open"]), 700.0, "v8 dense opening is at least 700 columns")

	var v7_canopy := _crown_stats(v7, CANOPY_BOX)
	var v8_canopy := _crown_stats(v8, CANOPY_BOX)
	h.greater(v8_canopy["open"], v7_canopy["open"], "v8 opens the canopy box")
	h.less(v8_canopy["multi"], v7_canopy["multi"], "v8 reduces 2+ crown overlap")
	h.less(v8_canopy["triple"], v7_canopy["triple"], "v8 reduces 3+ crown overlap")
	h.greater(v8_canopy["open"], 0.55, "v8 canopy box is at least 55%% open")
	h.greater(v8_canopy["covered"], 0.30, "v8 canopy box still has forest cover")

	h.section("M37 treeline preserved")
	var v8_line := _treeline(v8)
	var v7_line := _treeline(v7)
	h.greater(float(v8_line["trees"]), 100.0, "the v8 treeline sample has trees")
	h.eq(v8_line["above_root"], 0, "no v8 root exceeds the treeline")
	h.eq(v8_line["above_top"], 0, "no v8 full tree top exceeds the canopy ceiling")
	h.check(int(v8_line["max_root"]) <= int(v7_line["max_root"]),
		"v8 keeps the v7 root treeline or stays below it")
	h.check(int(v8_line["max_top"]) <= int(v7_line["max_top"]),
		"v8 keeps the v7 canopy ceiling or stays below it")

	h.section("M37 river and boundaries")
	var river_core := 0
	var river_core_trees := 0
	var river_outer := 0
	var river_outer_trees := 0
	for z in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
		for x in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
			var distance := v8._river_distance(x, z)
			var tree := _is_tree(int(v8.tree_at(x, z)["type"]))
			if distance < WorldGen.RIVER_BANK_LIMIT * WorldGen.M33_RIVER_CORE:
				river_core += 1
				river_core_trees += 1 if tree else 0
			elif distance < WorldGen.RIVER_BANK_LIMIT * WorldGen.M33_RIVER_OUTER:
				river_outer += 1
				river_outer_trees += 1 if tree else 0
	h.greater(float(river_core), 100.0, "the river core sample is large")
	h.eq(river_core_trees, 0, "the v8 river core has no trees")
	h.greater(float(river_outer), 100.0, "the river outer sample is large")
	h.greater(float(river_outer_trees) / maxf(1.0, float(river_outer)), 0.005,
		"v8 retains sparse river-outer trees")
	h.less(float(river_outer_trees) / maxf(1.0, float(river_outer)), 0.20,
		"v8 river-outer vegetation stays below 20%%")

	var seam_generator := WorldGen.new(17017, 8)
	var found := false
	for z in range(-64, 1):
		for x in range(40, 57):
			var data := seam_generator.tree_at(x, z)
			if not _is_tree(int(data["type"])):
				continue
			var radius := 5
			if _is_broadleaf(int(data["type"])):
				radius = int(data.get("canopy", 3)) + 2
			if x - radius <= 48 and x + radius >= 48:
				found = true
				break
		if found:
			break
	h.check(found, "a v8 crown crosses the x=48 border")
	var a := VoxelWorld.new(17017, 8)
	var b := VoxelWorld.new(17017, 8)
	var coords: Array[Vector3i] = []
	for cy in range(0, 7):
		for cz in range(2, 5):
			for cx in range(2, 5):
				coords.append(Vector3i(cx, cy, cz))
	for c: Vector3i in coords:
		a.ensure_chunk(c)
	for i in range(coords.size() - 1, -1, -1):
		b.ensure_chunk(coords[i])
	var mismatch := 0
	for c: Vector3i in coords:
		if (a.get_chunk(c) as ChunkData).blocks != (b.get_chunk(c) as ChunkData).blocks:
			mismatch += 1
	h.eq(mismatch, 0, "v8 chunks match across both load orders")

	h.section("M37 additional seed")
	var seed_b_a := WorldGen.new(424242, 8)
	var seed_b_b := WorldGen.new(424242, 8)
	var seed_b_difference := 0
	var seed_b_trees := 0
	var seed_b_forest := 0
	for z in range(-96, 97, 4):
		for x in range(-96, 97, 4):
			if int(seed_b_a.tree_at(x, z)["type"]) != int(seed_b_b.tree_at(x, z)["type"]):
				seed_b_difference += 1
			if seed_b_a.biome_at(x, z) == WorldGen.Biome.FOREST:
				seed_b_forest += 1
				if _is_tree(int(seed_b_a.tree_at(x, z)["type"])):
					seed_b_trees += 1
	h.eq(seed_b_difference, 0, "the additional seed is deterministic")
	h.greater(float(seed_b_forest), 100.0, "the additional seed has a forest sample")
	h.greater(float(seed_b_trees) / maxf(1.0, float(seed_b_forest)), 0.01,
		"the additional seed still has forest")
	var seed_b_line := _treeline(seed_b_a)
	h.eq(seed_b_line["above_root"], 0, "the additional seed keeps the root treeline")
	h.eq(seed_b_line["above_top"], 0, "the additional seed keeps the canopy ceiling")

	h.section("M37 save")
	var world := VoxelWorld.new(17017, 8)
	world.ensure_chunk(Vector3i(0, 4, 0))
	var save := SaveManager.new()
	var payload: Dictionary = save.to_dictionary(world, null, Inventory.new())
	h.eq(int(payload["terrain_generator_version"]), 8, "a v8 save records generator 8")
	h.finish()
